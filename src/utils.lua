-- ~/.hammerspoon/wifi_autoconfig/utils.lua
local M = {}
M.modulePath = debug.getinfo(1).source:match("@?(.*/)") or (os.getenv("HOME") .. "/.hammerspoon/wifi_autoconfig/")
local modulePath = M.modulePath
local logFile = modulePath .. "wifi_autoconfig.log"
-- 0 (not os.time()) so the very first log after a fresh load runs a cleanup
-- pass. That pass reads a file that is at most one session old, so it is cheap,
-- and it means a machine that never writes much still trims its log instead of
-- waiting a full week for the first trigger.
local lastCleanupTime = 0
local timer = require("hs.timer")
local dialog = require("hs.dialog")
local i18n = require("wifi_autoconfig.i18n")

function M.escapeHTML(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;"):gsub("'", "&#39;")
    return str
end

function M.escapeJS(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("\\", "\\\\"):gsub("'", "\\'"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return str
end

M.logFilePath = logFile

local function cleanupInterval()
    return 7 * 24 * 3600
end

-- Hard cap on the log file. Entries older than the retention window are
-- dropped, and if that is not enough (a burst of logging, or a very long
-- uptime) the newest MAX_LOG_LINES are kept and the rest discarded. Without
-- this the file is only ever appended to, so it grows without bound.
local MAX_LOG_LINES = 20000

function M.cleanOldLogs()
    local f = io.open(logFile, "r")
    if not f then return end
    local now = os.time()

    -- A log line may span several physical lines (a multi-line command output
    -- is written as several records), so a line without a timestamp belongs to
    -- the entry above it. lastEntryWithinRange tracks that entry's verdict.
    local kept = {}
    local keptCount = 0
    local lastEntryWithinRange = false
    -- Distinguishes "no timestamped entry seen yet" from "the last entry was
    -- dropped". Without it, a log file that starts with an orphan continuation
    -- line (or a truncated first record) would have that line silently deleted
    -- just because there was nothing above it to inherit a verdict from.
    local seenEntry = false

    for line in f:lines() do
        local keep = true
        local dateStr = line:match("%[(%d+%-%d+%-%d+ %d+:%d+:%d+)%]")
        if dateStr then
            seenEntry = true
            local y, m, d, h, mi, s = dateStr:match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")
            local yy, mm, dd, hh, mii, ss = tonumber(y), tonumber(m), tonumber(d), tonumber(h), tonumber(mi), tonumber(s)
            if yy and mm and dd and hh and mii and ss then
                local t = os.time{year=yy, month=mm, day=dd, hour=hh, min=mii, sec=ss}
                lastEntryWithinRange = (now - t <= cleanupInterval())
            else
                -- Unparseable timestamp: keep it rather than discarding data.
                lastEntryWithinRange = true
            end
            keep = lastEntryWithinRange
        elseif seenEntry then
            -- No timestamp of its own: this line is a continuation, so it lives
            -- or dies with the entry above it. Lines before the first timestamp
            -- (a truncated head) are kept - we cannot prove they are stale.
            keep = lastEntryWithinRange
        end

        if keep then
            keptCount = keptCount + 1
            kept[keptCount] = line
        end
    end
    f:close()

    -- Enforce the size cap by keeping only the tail.
    if keptCount > MAX_LOG_LINES then
        local overflow = keptCount - MAX_LOG_LINES
        local trimmed = {}
        for i = overflow + 1, keptCount do
            trimmed[i - overflow] = kept[i]
        end
        kept = trimmed
        keptCount = MAX_LOG_LINES
        M.log(("log truncated: dropped %d oldest lines (cap %d)"):format(overflow, MAX_LOG_LINES))
    end

    local wf = io.open(logFile, "w")
    if wf then
        -- table.concat on an empty table yields "", and appending "\n" would
        -- leave a blank line behind, so only terminate when there is content.
        if keptCount > 0 then
            wf:write(table.concat(kept, "\n") .. "\n")
        end
        wf:close()
    end
end

function M.log(message)
    local now = os.time()
    if now - lastCleanupTime >= cleanupInterval() then
        -- Stamp BEFORE cleaning: cleanOldLogs() itself calls M.log() when it
        -- trims, and updating afterwards would let that nested call see a stale
        -- timestamp and start the whole cycle over (infinite recursion).
        lastCleanupTime = now
        M.cleanOldLogs()
    end
    if message == nil then message = "<nil>" end
    local f = io.open(logFile, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(message) .. "\n")
        f:close()
    end
end

-- hs.dialog.blockAlert runs a nested modal loop and blocks this thread until the user
-- answers. Several paths can reach it while a dialog is already up (a URL event from the
-- editor, a timer, another Wi-Fi switch), and a second modal on top of the first leaves
-- Hammerspoon with a window no button can dismiss. One answer at a time: a caller whose
-- dialog was skipped gets nil, which every caller already treats as "not confirmed".
local modalOpen = false

function M.blockAlertOnce(title, message, button1, button2)
    if modalOpen then
        M.log(i18n.t("log_modal_blocked", tostring(title)))
        return nil
    end
    modalOpen = true
    local ok, choice = pcall(function()
        return dialog.blockAlert(title, message, button1, button2)
    end)
    modalOpen = false
    if not ok then
        M.log(i18n.t("log_modal_error", tostring(choice)))
        return nil
    end
    return choice
end

-- One-shot timers that are not referenced anywhere get collected. A timer object is
-- ordinary userdata: the only thing keeping it alive is the value hs.timer.doAfter returns,
-- and this function used to drop it, so a scheduled report could simply never arrive - the
-- callback and its closure are reachable only through the timer, and nothing complains when
-- a timer does not fire. Hold each one until it has run.
local pendingWaits = {}

function M.wait(seconds, callback)
    if not callback then
        M.log(i18n.t("log_wait_no_callback"))
        return
    end
    local holder = {}
    -- Registered before the call and keyed on the holder rather than on the timer: a timer
    -- whose delay has already come due can hand back nothing, and nil is not a valid key.
    pendingWaits[holder] = holder
    holder.timer = timer.doAfter(seconds, function()
        pendingWaits[holder] = nil
        callback()
    end)
    return holder.timer
end

function M.waitForCondition(checkFn, timeout, interval, callback)
    if not checkFn or type(checkFn) ~= "function" then
        M.log(i18n.t("log_waitfor_check_invalid"))
        if callback then callback(false) end
        return
    end

    if not callback or type(callback) ~= "function" then
        M.log(i18n.t("log_waitfor_cb_invalid"))
        return
    end

    local elapsed = 0
    local pollInterval = interval or 0.5
    local maxTimeout = timeout or 15
    local t = nil
    local done = false

    local function check()
        if done then return end

        if not checkFn or not callback then
            done = true
            if t then t:stop() end
            M.log(i18n.t("log_waitfor_cb_lost"))
            return
        end

        if checkFn() then
            done = true
            if t then t:stop() end
            callback(true)
            return
        end

        elapsed = elapsed + pollInterval
        if elapsed >= maxTimeout then
            done = true
            if t then t:stop() end
            M.log(i18n.t("log_waitfor_timeout", tostring(elapsed)))
            callback(false)
            return
        end
    end

    check()

    if not done then
        t = timer.new(pollInterval, check)
        t:start()
    end
end

return M
