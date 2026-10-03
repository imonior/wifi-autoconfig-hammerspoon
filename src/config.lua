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

local function isValidDNSEntry(str)
    if not str or str == "" then return true end
    for entry in string.gmatch(str, "[^,%s]+") do
        if not isValidIPv4(entry) then return false end
    end
    return true
end

local function isValidIPv6(str)
    if not str or str == "" then return false end
    if not str:match("^[%x:%%]+$") then return false end
    if str:match(":::") then return false end
    local colons = 0
    for _ in str:gmatch(":") do colons = colons + 1 end
    if colons > 7 then return false end
    return true
end

local function isValidIPv6Prefix(str)
    if not str or str == "" then return false end
    local n = tonumber(str)
    return n and n >= 1 and n <= 128
end

local function validateConfig(d)
    if d.mode == "manual" then
        if not isValidIPv4(d.ip) then return false, i18n.t("ui_invalid_ip") end
        if d.netmask and d.netmask ~= "" and not isValidIPv4(d.netmask) then return false, i18n.t("ui_invalid_netmask") end
        if d.gateway and d.gateway ~= "" and not isValidIPv4(d.gateway) then return false, i18n.t("ui_invalid_gateway") end
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

function M.read()
    local f = io.open(M.path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        M.current = json.decode(content) or {}
    else 
        M.current = {}
        M.write()
    end
    return M.current
end

function M.write()
    local f = io.open(M.path, "w")
    if f then
        f:write(json.encode(M.current, true))
        f:close()
    end
end

function M.registerURLSchemes(onConfigChangedCallback, onForceApply, onFetchInfo, onCloseEditor)
    urlevent.bind("save_wifi_scene", function(_, params)
        local d = nil
        if params.data then
            local ok, decoded = pcall(json.decode, params.data)
            d = ok and decoded
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
            M.current[d.ssid] = {
                mode = d.mode, ip = d.ip, netmask = d.netmask, gateway = d.gateway, dns = d.dns,
                v6mode = d.v6mode, ipv6 = d.ipv6, v6prefix = d.v6prefix, v6gateway = d.v6gateway
            }
            M.write()
            alert.show(i18n.t("ui_save_success") .. ": " .. d.ssid)
            utils.log(i18n.t("log_saved_config", tostring(d.ssid)))
            if onConfigChangedCallback then onConfigChangedCallback() end
        end
    end)

    urlevent.bind("delete_wifi_scene", function(eventName, params)
        local ssid = nil
        if params.data then
            local ok, d = pcall(json.decode, params.data)
            ssid = ok and d and d.ssid
        else
            ssid = params.ssid
        end

        if ssid then
            M.current[ssid] = nil
            M.write()
            alert.show(i18n.t("ui_delete_success") .. ": " .. ssid)
            utils.log(i18n.t("log_deleted_config", tostring(ssid)))
            if onConfigChangedCallback then onConfigChangedCallback() end
        end
    end)

    local function handleForceApply(params)
        local data = nil
        if params.data then
            local decoded = params.data:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
            data = json.decode(decoded)
        end
        return data
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