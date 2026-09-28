-- ~/.hammerspoon/wifi_autoconfig/init.lua
local menubar = require("hs.menubar")
local wifi = require("hs.wifi")
local json = require("hs.json")
local dialog = require("hs.dialog")
local styledtext = require("hs.styledtext")
local image = require("hs.image")
local timer = require("hs.timer")
local core = require("wifi_autoconfig.core")
local config = require("wifi_autoconfig.config")
local utils = require("wifi_autoconfig.utils")
local ui = require("wifi_autoconfig.ui.web_view")
local i18n = require("wifi_autoconfig.i18n")
local menuBuilder = require("wifi_autoconfig.menu_builder")
local networkApply = require("wifi_autoconfig.network_apply")

local M = {}
M.VERSION = "3.0.0"

local modulePath = utils.modulePath
local logFilePath = utils.logFilePath
local currentSSID = nil
M.menuBarItem = nil
M.wifiWatcher = nil

-- Menu rebuild is triggered on every click; keep a short TTL so that repeated
-- clicks don't fork the same 20+ shell processes over and over.
local STATUS_CACHE_TTL = 5
local cacheTimestamp = 0

local cachedNetworkStatus = {
    wifiStatus = nil,
    wifiInterface = nil,
    ipv4 = { ip = nil, gw = nil, nm = nil },
    ipv6 = { mode = nil, ip = nil, prefix = nil, gw = nil },
    dns = nil,
    vpnInfo = nil,
    isDarkMode = nil
}

local function isCacheFresh()
    return cacheTimestamp > 0 and (os.time() - cacheTimestamp) < STATUS_CACHE_TTL
end

local function invalidateStatusCache()
    cacheTimestamp = 0
end

local function refreshNetworkStatusCache(force)
    if not force and isCacheFresh() then
        return
    end

    cachedNetworkStatus.wifiStatus = core.getCurrentWiFiStatus()
    cachedNetworkStatus.wifiInterface = core.getWiFiServiceName()

    local ip, gw, nm, v4mode = core.getCurrentIPv4Info(cachedNetworkStatus.wifiInterface)
    cachedNetworkStatus.ipv4 = { ip = ip, gw = gw, nm = nm, mode = v4mode }

    local v6mode, v6ip, v6prefix, v6gw = core.getCurrentIPv6Info(cachedNetworkStatus.wifiInterface)
    cachedNetworkStatus.ipv6 = { mode = v6mode, ip = v6ip, prefix = v6prefix, gw = v6gw }

    cachedNetworkStatus.dns = core.getActiveDNS()
    cachedNetworkStatus.vpnInfo = core.getVPNInfo()
    cachedNetworkStatus.isDarkMode = menuBuilder.detectDarkMode()

    cacheTimestamp = os.time()
end

function M.performNetworkAudit()
    local status = core.getCurrentWiFiStatus()
    if not status.connected or not status.ssid then
        utils.log(i18n.t("log_wifi_sleep"))
        return
    end

    local ssid = status.ssid
    if ssid == currentSSID then 
        return 
    end

    utils.log(i18n.t("log_ssid_change", tostring(currentSSID), ssid))
    currentSSID = ssid
    invalidateStatusCache()

    config.read()
    networkApply.applyNetworkStrategy(ssid)
end

local function buildConfigSummary(data)
    local dnsValue = data.dns or ""
    if type(dnsValue) == "table" then
        dnsValue = table.concat(dnsValue, "\n")
    end

    local lines = {}
    if data.mode == "manual" then
        lines = {
            i18n.t("label_ipv4"),
            i18n.t("label_mode") .. ": " .. i18n.t("ui_mode_static"),
            i18n.t("label_address") .. ": " .. tostring(data.ip),
            i18n.t("label_netmask") .. ": " .. tostring(data.netmask),
            i18n.t("label_gateway") .. ": " .. tostring(data.gateway),
            "",
            i18n.t("label_ipv6"),
            i18n.t("label_mode") .. ": " .. tostring(data.v6mode),
            "",
            i18n.t("label_dns"),
            dnsValue
        }
    else
        local dnsInfo = dnsValue ~= "" and dnsValue or i18n.t("auto")
        lines = {
            i18n.t("label_ipv4"),
            i18n.t("label_mode") .. ": " .. i18n.t("ui_mode_dhcp"),
            "",
            i18n.t("label_ipv6"),
            i18n.t("label_mode") .. ": " .. tostring(data.v6mode),
            "",
            i18n.t("label_dns"),
            dnsInfo
        }
    end

    return i18n.t("popup_confirm_force_apply_detail") .. "\n\n" .. table.concat(lines, "\n")
end

local function handleForceApply(data)
    local wifiInterface = core.getWiFiServiceName()

    if not data then
        utils.log(i18n.t("log_force_apply_no_data"))
        return
    end

    utils.log(i18n.t("log_force_apply_with_data", json.encode(data)))

    local choice = dialog.blockAlert(
        i18n.t("popup_title_confirm_force_apply"),
        buildConfigSummary(data),
        i18n.t("popup_confirm"),
        i18n.t("popup_cancel")
    )

    if choice ~= i18n.t("popup_confirm") then
        return
    end

    currentSSID = data.ssid
    invalidateStatusCache()

    networkApply.applyConfigToInterface(wifiInterface, data, function()
        utils.wait(2, function()
            local report = networkApply.buildNetworkReport(i18n.t("config_source_editor"))
            ui.showPopup("success", i18n.t("popup_title_force_apply_success"), report)
            ui.syncHardwareStatusToUI()
        end)
    end)
end

local function buildMenuBar()
    if not M.menuBarItem then
        M.menuBarItem = menubar.new()
    end
    
    if M.menuBarItem then
        local wifiIcon = image.imageFromPath(modulePath .. "ui/icons/wifi.svg")
        if wifiIcon then
            M.menuBarItem:setIcon(wifiIcon, false)
        else
            M.menuBarItem:setTitle("📶")
        end
        
        M.menuBarItem:setMenu(function()
            refreshNetworkStatusCache(false)

            local success, result = pcall(function()
                return menuBuilder.buildNetworkStatusMenuItems(cachedNetworkStatus)
            end)
            
            local menuItems = {}
            if success and type(result) == "table" then
                menuItems = result
            elseif not success then
                utils.log("buildNetworkStatusMenuItems error: " .. tostring(result))
            end
            
            table.insert(menuItems, { 
                title = styledtext.new("⚙️ " .. i18n.t("menu_open_settings"), { font = { size = 12 } }),
                fn = function() ui.showEditor(config.current) end
            })
            table.insert(menuItems, { 
                title = styledtext.new("📋 " .. i18n.t("menu_view_logs"), { font = { size = 12 } }),
                fn = function() 
                    local f = io.open(logFilePath, "r")
                    local content = ""
                    if f then
                        content = f:read("*a")
                        f:close()
                    end
                    ui.showPopup("log", i18n.t("recent_system_logs"), content) 
                end
            })
            table.insert(menuItems, { 
                title = styledtext.new("🔄 " .. i18n.t("menu_update_dhcp"), { font = { size = 12 } }),
                fn = function() networkApply.setCurrentNetworkToDHCP() end
            })
            table.insert(menuItems, { 
                title = styledtext.new("🔍 " .. i18n.t("menu_force_detect"), { font = { size = 12 } }),
                fn = function() 
                    utils.log(i18n.t("log_manual_detect"))
                    currentSSID = nil
                    invalidateStatusCache()
                    M.performNetworkAudit()
                end
            })
            
            return menuItems
        end)
    end
end

function M.refreshMenuBar()
    if M.menuBarItem then
        buildMenuBar()
    end
end

function M.init()
    config.read()
    
    config.registerURLSchemes(
        function() 
            if ui.editorView then 
                ui.refreshEditor() 
            else 
                ui.showEditor(config.current) 
            end 
        end,
        handleForceApply,
        function()
            ui.syncHardwareStatusToUI()
        end,
        function()
            utils.log(i18n.t("log_close_editor"))
            ui.closeEditor()
        end
    )
    
    buildMenuBar()
    
    M.wifiWatcher = wifi.watcher.new(M.performNetworkAudit)
    M.wifiWatcher:start()
    
    M.performNetworkAudit()
    
    timer.doAfter(2, function()
        ui.syncHardwareStatusToUI()
    end)
    
    utils.log(i18n.t("log_init_success"))
end

_G.WiFiAutoConfigModule = M
_G.WiFiAutoConfigModule.init()

return M
