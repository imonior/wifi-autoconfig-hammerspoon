-- ~/.hammerspoon/wifi_autoconfig/config.lua
local json = require("hs.json")
local alert = require("hs.alert")
local urlevent = require("hs.urlevent")
local utils = require("wifi_autoconfig.utils")
local i18n = require("wifi_autoconfig.i18n")

local M = {}
local modulePath = utils.modulePath
M.path = modulePath .. "config.json"
M.current = {}

-- True while the on-disk config could not be parsed. In that state M.current is
-- stale and writes are refused, so an unreadable file can never be replaced by
-- the empty/partial table that resulted from failing to read it.
M.degraded = false

-- Flattens a dns value that arrived as a JSON array. Nested arrays are walked too,
-- and values that are neither text nor number are dropped: tostring() of a table
-- would otherwise become a DNS server address sent to networksetup.
local function collectDns(value, out)
    local kind = type(value)
    if kind == "table" then
        for _, item in ipairs(value) do collectDns(item, out) end
    elseif kind == "string" then
        out[#out + 1] = value
    elseif kind == "number" or kind == "boolean" then
        out[#out + 1] = tostring(value)
    end
end

local function dnsToString(dns)
    if dns == nil then return nil end
    if type(dns) ~= "table" then return tostring(dns) end
    local parts = {}
    collectDns(dns, parts)
    return table.concat(parts, ",")
end

-- Everything downstream of here treats an entry's dns field as a string:
-- isValidDNSEntry and core.setDNSServers both call string.gmatch on it directly.
-- A dns list written as a JSON array therefore has to be flattened on the way in.
--
-- mode gets a default for the same reason: policies written before this field was
-- always present mean "get an address automatically", and naming that here keeps
-- validateConfig strict (an entry that says "static" is a typo, not a mode).
-- v6mode deliberately has NO default - "no IPv6 policy" means "leave the interface's
-- IPv6 alone", and defaulting it would switch IPv6 off or reconfigure it by surprise.
local function normalizeEntry(entry)
    entry.dns = dnsToString(entry.dns)
    if entry.mode == nil or entry.mode == "" then
        entry.mode = "dhcp"
    end
    return entry
end

local function isValidIPv4(str)
    if not str or str == "" then return false end
    local a, b, c, d = str:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return false end
    for _, v in ipairs({a, b, c, d}) do
        local n = tonumber(v)
        if not n or n < 0 or n > 255 then return false end
    end
    return true
end

-- Validates that an IPv4 netmask is contiguous: the 32-bit value must be a run of 1s
-- followed by a run of 0s (e.g. 255.255.255.0 is valid; 255.0.255.0 is not).
local function isValidNetmask(str)
    if not isValidIPv4(str) then return false end
    local a, b, c, d = str:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    -- Convert to a 32-bit integer using arithmetic (no bit32 dependency).
    local mask = tonumber(a) * 16777216 + tonumber(b) * 65536 + tonumber(c) * 256 + tonumber(d)
    -- A contiguous mask has the form ~((1 << n) - 1) for some n in [0..32].
    -- Equivalently: (mask & (mask + 1)) == 0 when mask != 0xFFFFFFFF.
    -- Using bitwise AND via arithmetic: mask & (mask+1) can be computed with % operator.
    -- But simpler: iterate through known valid masks.
    local validMasks = {
        0x00000000, 0x80000000, 0xC0000000, 0xE0000000, 0xF0000000,
        0xF8000000, 0xFC000000, 0xFE000000, 0xFF000000, 0xFF800000,
        0xFFC00000, 0xFFE00000, 0xFFF00000, 0xFFF80000, 0xFFFC0000,
        0xFFFE0000, 0xFFFF0000, 0xFFFF8000, 0xFFFFC000, 0xFFFFE000,
        0xFFFFF000, 0xFFFFF800, 0xFFFFFC00, 0xFFFFFE00, 0xFFFFFF00,
        0xFFFFFF80, 0xFFFFFFC0, 0xFFFFFFE0, 0xFFFFFFF0, 0xFFFFFFF8,
        0xFFFFFFFC, 0xFFFFFFFE, 0xFFFFFFFF
    }
    for _, vm in ipairs(validMasks) do
        if mask == vm then return true end
    end
    return false
end

local function isValidDNSEntry(str)
    if not str or str == "" then return true end
    for entry in string.gmatch(str, "[^,%s]+") do
        if not isValidIPv4(entry) then return false end
    end
    return true
end

local function isValidIPv6(str)
    if not str or str == "" then return false end
    -- Strip optional zone ID (e.g. fe80::1%en0).
    local addr = str:gsub("%%[%w]+$", "")
    -- Only hex digits and colons allowed.
    if not addr:match("^[%x:]+$") then return false end
    -- No triple colons.
    if addr:match(":::") then return false end
    -- At most one "::" expansion.
    local doubleColonCount = 0
    for _ in addr:gmatch("::") do doubleColonCount = doubleColonCount + 1 end
    if doubleColonCount > 1 then return false end
    -- Split on ":" and validate each group (max 4 hex chars, max 8 groups without ::).
    local groups = {}
    for g in addr:gmatch("[^:]+") do
        if #g > 4 then return false end
        if not g:match("^%x+$") then return false end
        table.insert(groups, g)
    end
    -- With no "::", must have exactly 8 groups. With "::", at most 7.
    if doubleColonCount == 0 and #groups ~= 8 then return false end
    if doubleColonCount == 1 and #groups > 7 then return false end
    return true
end

local function isValidIPv6Prefix(str)
    if not str or str == "" then return false end
    local n = tonumber(str)
    return n and n >= 1 and n <= 128
end

local function validateConfig(d)
    d.dns = dnsToString(d.dns)

    -- Everything downstream branches on mode == "manual" and treats anything else as
    -- DHCP, so a typo ("static", "Manual") would silently downgrade a static network.
    if d.mode ~= "dhcp" and d.mode ~= "manual" then
        return false, i18n.t("ui_invalid_mode")
    end

    if d.mode == "manual" then
        if not isValidIPv4(d.ip) then return false, i18n.t("ui_invalid_ip") end
        if d.netmask and d.netmask ~= "" and not isValidNetmask(d.netmask) then return false, i18n.t("ui_invalid_netmask") end
        -- -setmanual takes the router as its fourth argument, and shellQuote(nil)
        -- produces the literal text 'nil', so a missing gateway used to be sent to
        -- sudo as `-setmanual Wi-Fi 10.0.0.5 255.255.255.0 nil`.
        if d.gateway == nil or d.gateway == "" then
            return false, i18n.t("ui_gateway_required")
        elseif not isValidIPv4(d.gateway) then
            return false, i18n.t("ui_invalid_gateway")
        end
    end

    -- An unrecognised v6mode must not reach configureIPv6 either: "automatic", "off"
    -- and "manual" do very different things to the interface, and empty/absent means
    -- "leave IPv6 as the system set it".
    if d.v6mode ~= nil and d.v6mode ~= ""
        and d.v6mode ~= "automatic" and d.v6mode ~= "off" and d.v6mode ~= "manual" then
        return false, i18n.t("ui_invalid_v6mode")
    end

    if d.v6mode == "manual" then
        if not d.ipv6 or d.ipv6 == "" then return false, i18n.t("ui_invalid_ipv6") end
        if not isValidIPv6(d.ipv6) then return false, i18n.t("ui_invalid_ipv6") end
        if not d.v6prefix or d.v6prefix == "" then return false, i18n.t("ui_invalid_v6prefix") end
        if not isValidIPv6Prefix(d.v6prefix) then return false, i18n.t("ui_invalid_v6prefix") end
        if not d.v6gateway or d.v6gateway == "" then return false, i18n.t("ui_invalid_v6gateway") end
        if not isValidIPv6(d.v6gateway) then return false, i18n.t("ui_invalid_v6gateway") end
    end
    if d.dns and d.dns ~= "" and not isValidDNSEntry(d.dns) then return false, i18n.t("ui_invalid_dns") end
    return true
end

-- Exported so the force-apply path can validate too. Previously this was
-- local and only ran on the save path, which meant a hand-typed bad value in
-- the editor went straight to `sudo networksetup` with no check at all.
M.validateConfig = validateConfig

-- Returns the file's contents, or nil when it cannot be opened.
local function readRaw()
    local f = io.open(M.path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

-- A policy file is always a JSON object. hs.json.decode returns nil rather than
-- raising on malformed input, so anything that is not a table means unreadable.
local function decodeTable(content)
    if not content or content:match("^%s*$") then return nil end
    local decoded = json.decode(content)
    if type(decoded) == "table" then return decoded end
    return nil
end

-- The exact bytes the user already turned the dialog down on. Blocking again on
-- every Wi-Fi switch with the same broken file would only teach them to click
-- through the one dialog that matters.
local dismissedContent = nil

-- Same idea for a file that has gone missing: true once the user chose to deal
-- with it later, cleared as soon as the file is readable again.
local missingDismissed = nil

-- Forward declaration: a broken file can turn into a missing one while the user is
-- looking at the repair dialog, and the two flows hand the file over to each other.
local waitForMissingFile

local function loadedPolicyCount()
    local n = 0
    for _ in pairs(M.current) do n = n + 1 end
    return n
end

-- Modal until the user has repaired the file (re-checked on every retry) or
-- chosen to deal with it later. Returns a decoded table, or nil to stay degraded.
local function waitForRepair(content)
    utils.log(i18n.t("log_config_parse_failed", M.path))

    if content == dismissedContent then
        utils.log(i18n.t("log_config_deferred", M.path))
        return nil
    end

    local message = i18n.t("ui_config_unreadable") .. "\n" .. M.path
    while true do
        local choice = utils.blockAlertOnce(
            i18n.t("ui_config_unreadable_title"),
            message,
            i18n.t("popup_retry_read"),
            i18n.t("popup_handle_later")
        )

        if choice ~= i18n.t("popup_retry_read") then
            dismissedContent = content
            utils.log(i18n.t("log_config_deferred", M.path))
            return nil
        end

        local fresh = readRaw()
        local decoded = decodeTable(fresh)
        if decoded then
            dismissedContent = nil
            utils.log(i18n.t("log_config_recovered", M.path))
            return decoded
        end

        if fresh == nil or fresh:match("^%s*$") then
            -- The broken file was deleted or truncated while the dialog was open. There
            -- is nothing left to repair, but the loaded policies are still at risk, so
            -- the missing-file flow takes over and decides what is safe.
            return waitForMissingFile()
        end

        message = i18n.t("ui_config_still_unreadable") .. "\n" .. M.path
    end
end

-- The file is absent or carries no bytes at all. That is only harmless when this
-- module has nothing to lose: with policies loaded, accepting it would drop every
-- one of them and the next switch would find no policy for the SSID, which the
-- fallback branch answers by forcing the interface onto DHCP. A static network would
-- lose its address without a word. So the policies stay in memory, writing stays
-- refused, and the user gets the chance to bring the file back.
function waitForMissingFile()
    local count = loadedPolicyCount()
    if count == 0 then
        -- Nothing to protect: rebuild the file and carry on. This is the first-run case.
        missingDismissed = nil
        return {}
    end

    utils.log(i18n.t("log_config_missing", count, M.path))

    if missingDismissed then
        utils.log(i18n.t("log_config_deferred", M.path))
        return nil
    end

    local message = i18n.t("ui_config_missing", count) .. "\n" .. M.path
    while true do
        local choice = utils.blockAlertOnce(
            i18n.t("ui_config_missing_title"),
            message,
            i18n.t("popup_retry_read"),
            i18n.t("popup_handle_later")
        )

        if choice ~= i18n.t("popup_retry_read") then
            missingDismissed = true
            utils.log(i18n.t("log_config_deferred", M.path))
            return nil
        end

        local fresh = readRaw()
        local decoded = decodeTable(fresh)
        if decoded then
            missingDismissed = nil
            dismissedContent = nil
            utils.log(i18n.t("log_config_recovered", M.path))
            return decoded
        end

        if fresh and not fresh:match("^%s*$") then
            -- The file came back with bytes that do not parse: that is the other flow.
            return waitForRepair(fresh)
        end

        message = i18n.t("ui_config_still_missing") .. "\n" .. M.path
    end
end

function M.read()
    local content = readRaw()
    local decoded
    local rebuildFile = false

    if content == nil or content:match("^%s*$") then
        -- Absent (first run, or deleted since the last read) or empty. waitForMissingFile
        -- tells those apart by what is still loaded: with no policies it returns an empty
        -- table so the file gets rebuilt, with policies it refuses to trade them for one.
        decoded = waitForMissingFile()
        if not decoded then
            M.degraded = true
            return M.current
        end
        rebuildFile = true
    else
        decoded = decodeTable(content)
        if not decoded then
            -- Leave the file exactly as it is: the user's policies are still in it, one
            -- comma away from working. M.current keeps whatever the last successful read
            -- produced, and M.write() refuses until it parses again.
            decoded = waitForRepair(content)
            if not decoded then
                M.degraded = true
                return M.current
            end
        end
    end

    M.degraded = false
    missingDismissed = nil
    local result = {}
    for ssid, entry in pairs(decoded) do
        if type(entry) == "table" then
            result[ssid] = normalizeEntry(entry)
        else
            utils.log(i18n.t("log_config_entry_ignored", tostring(ssid)))
        end
    end
    M.current = result
    if rebuildFile then
        -- The file held nothing, so writing what was loaded back out loses nothing and
        -- leaves a first-run or emptied file in place again.
        M.write()
    end
    return M.current
end

-- Returns true when the table really reached the disk. Callers must not report
-- success without checking: while degraded the write below is refused outright.
function M.write()
    if M.degraded then
        utils.log(i18n.t("log_config_write_blocked", M.path))
        return false
    end

    -- The file can stop parsing after the last successful read - hand-edited while
    -- the editor was open, or edited by another tool. Saving then would push the
    -- in-memory table over whatever the user just wrote, which is the exact loss
    -- this module is supposed to make impossible, so the disk is re-checked here
    -- rather than trusting an M.degraded flag that was computed from older bytes.
    local onDisk = readRaw()
    if onDisk and not onDisk:match("^%s*$") and not decodeTable(onDisk) then
        M.degraded = true
        dismissedContent = nil
        utils.log(i18n.t("log_config_parse_failed", M.path))
        return false
    end

    local encoded = json.encode(M.current, true)
    if not encoded then
        utils.log(i18n.t("log_config_write_failed"))
        return false
    end

    local f = io.open(M.path, "w")
    if not f then
        utils.log(i18n.t("log_config_write_failed"))
        return false
    end
    f:write(encoded)
    f:close()
    return true
end

function M.registerURLSchemes(onConfigChangedCallback, onForceApply, onFetchInfo, onCloseEditor)
    urlevent.bind("save_wifi_scene", function(_, params)
        local d = nil
        if params.data then
            local ok, decoded = pcall(json.decode, params.data)
            -- A JSON scalar decodes cleanly, and indexing a number raises, so only a
            -- table can be a policy payload.
            d = (ok and type(decoded) == "table") and decoded or nil
        elseif params.ssid then
            d = params
        end
        if d and d.ssid then
            local valid, errMsg = validateConfig(d)
            if not valid then
                alert.show(i18n.t("ui_validation_error") .. ": " .. errMsg)
                utils.log(i18n.t("log_validation_failed", tostring(d.ssid), errMsg))
                return
            end
            local previous = M.current[d.ssid]
            M.current[d.ssid] = normalizeEntry({
                mode = d.mode, ip = d.ip, netmask = d.netmask, gateway = d.gateway, dns = d.dns,
                v6mode = d.v6mode, ipv6 = d.ipv6, v6prefix = d.v6prefix, v6gateway = d.v6gateway
            })
            if not M.write() then
                M.current[d.ssid] = previous
                utils.blockAlertOnce(
                    i18n.t("ui_config_unreadable_title"),
                    i18n.t("ui_save_failed_degraded") .. "\n" .. M.path,
                    i18n.t("popup_ok")
                )
                return
            end
            alert.show(i18n.t("ui_save_success") .. ": " .. d.ssid)
            utils.log(i18n.t("log_saved_config", tostring(d.ssid)))
            if onConfigChangedCallback then onConfigChangedCallback() end
        end
    end)

    urlevent.bind("delete_wifi_scene", function(eventName, params)
        local ssid = nil
        if params.data then
            local ok, d = pcall(json.decode, params.data)
            ssid = (ok and type(d) == "table") and d.ssid or nil
        else
            ssid = params.ssid
        end

        if ssid then
            -- The in-memory removal is rolled back if the write is refused: the file
            -- on disk is authoritative while degraded, so the editor must keep showing
            -- a policy that still exists there.
            local removed = M.current[ssid]
            M.current[ssid] = nil
            if not M.write() then
                M.current[ssid] = removed
                utils.blockAlertOnce(
                    i18n.t("ui_config_unreadable_title"),
                    i18n.t("ui_save_failed_degraded") .. "\n" .. M.path,
                    i18n.t("popup_ok")
                )
                return
            end
            alert.show(i18n.t("ui_delete_success") .. ": " .. ssid)
            utils.log(i18n.t("log_deleted_config", tostring(ssid)))
            if onConfigChangedCallback then onConfigChangedCallback() end
        end
    end)

    -- params.data has already been percent-decoded once by hs.urlevent before it
    -- reaches this callback, so decoding it a second time here corrupted any literal
    -- "%XX" sequence in an SSID (a name like "office%41") and left json.decode
    -- returning nil - the force-apply button then silently did nothing. The save
    -- handler above has always decoded exactly once; both paths now agree.
    local function handleForceApply(params)
        if not params.data then return nil end
        local ok, decoded = pcall(json.decode, params.data)
        if ok and type(decoded) == "table" then return decoded end
        return nil
    end

    -- The editor only ever calls force_apply_network_with_confirm; the bare
    -- force_apply_network handler was dead code and has been removed.
    urlevent.bind("force_apply_network_with_confirm", function(eventName, params)
        if onForceApply then onForceApply(handleForceApply(params)) end
    end)

    urlevent.bind("get_current_network_info", function()
        if onFetchInfo then onFetchInfo() end
    end)
    
    urlevent.bind("close_editor", function()
        if onCloseEditor then onCloseEditor() end
    end)
end

return M