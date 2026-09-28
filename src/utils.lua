-- ~/.hammerspoon/wifi_autoconfig/utils.lua
local M = {}
M.modulePath = debug.getinfo(1).source:match("@?(.*/)") or (os.getenv("HOME") .. "/.hammerspoon/wifi_autoconfig/")
local modulePath = M.modulePath
local logFile = modulePath .. "wifi_autoconfig.log"
local lastCleanupTime = os.time()
local timer = require("hs.timer")
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

function M.cleanOldLogs()
    local f = io.open(logFile, "r")
    if not f then return end
    local now = os.time()
    local lines = {}
    local lastEntryWithinRange = false
    for line in f:lines() do
        local dateStr = line:match("%[(%d+%-%d+%-%d+ %d+:%d+:%d+)%]")
        if dateStr then
            local year, month, day, hour, min, sec = dateStr:match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")
            local y, m, d, h, mi, s = tonumber(year), tonumber(month), tonumber(day), tonumber(hour), tonumber(min), tonumber(sec)
            if y and m and d and h and mi and s then
                local t = os.time{year=y, month=m, day=d, hour=h, min=mi, sec=s}
                if now - t <= cleanupInterval() then
                    table.insert(lines, line)
                    lastEntryWithinRange = true
                else
                    lastEntryWithinRange = false
                end
            else
                table.insert(lines, line)
                lastEntryWithinRange = true
            end
        else
            if lastEntryWithinRange then
                table.insert(lines, line)
            end
        end
    end
    f:close()
    local wf = io.open(logFile, "w")
    if wf then
        wf:write(table.concat(lines, "\n") .. "\n")
        wf:close()
    end
end

function M.log(message)
    local now = os.time()
    if now - lastCleanupTime >= cleanupInterval() then
        M.cleanOldLogs()
        lastCleanupTime = now
    end
    if message == nil then message = "<nil>" end
    local f = io.open(logFile, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(message) .. "\n")
        f:close()
    end
end

function M.wait(seconds, callback)
    if not callback then
        M.log(i18n.t("log_wait_no_callback"))
        return
    end
    timer.doAfter(seconds, callback)
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

function M.executeWithRetry(cmdFn, checkFn, maxRetries, delay, callback)
    if not cmdFn or type(cmdFn) ~= "function" then
        M.log(i18n.t("log_retry_cmd_invalid"))
        if callback then callback(false) end
        return
    end

    if not callback or type(callback) ~= "function" then
        M.log(i18n.t("log_retry_cb_invalid"))
        return
    end

    local retries = 0
    local maxAttempts = maxRetries or 3
    local waitDelay = delay or 1
    local t = nil
    local done = false

    local function execute()
        if done then return end

        if not cmdFn or not callback then
            done = true
            if t then t:stop() end
            M.log(i18n.t("log_retry_cb_lost"))
            return
        end

        local ok, result = cmdFn()
        if ok and (not checkFn or checkFn()) then
            done = true
            if t then t:stop() end
            callback(true, result)
            return
        end

        retries = retries + 1
        if retries >= maxAttempts then
            done = true
            if t then t:stop() end
            M.log(i18n.t("log_retry_exhausted"))
            callback(false, result)
            return
        end

        M.log(i18n.t("log_retry_attempt", retries, tostring(waitDelay)))
    end

    execute()

    if not done then
        t = timer.new(waitDelay, execute)
        t:start()
    end
end

return M
