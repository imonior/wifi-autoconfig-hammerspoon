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
local panel = require("wifi_autoconfig.panel")

local M = {}
M.VERSION = "3.2.0"

-- The status list is drawn by panel.lua on its own dark surface. Set this to
-- false to go back to the native hs.menubar menu: it keeps the system menu
-- material (light grey in light appearance), which is what made the amber and
-- the green unreadable, and it cannot stop informational rows from lighting up
-- on hover.
local USE_PANEL_MENU = true

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

-- Row model for the self-drawn panel: the status rows come from the shared
-- builder, then the four commands are appended as the interactive section.
local function buildPanelModel()
    refreshNetworkStatusCache(false)

    local ok, rows = pcall(function()
        return menuBuilder.buildStatusRows(cachedNetworkStatus)
    end)
    if not ok or type(rows) ~= "table" then
        utils.log("buildStatusRows error: " .. tostring(rows))
        rows = {}
    end

    -- buildStatusRows() already closes with a separator, so the commands can
    -- follow straight away.
    rows[#rows + 1] = { kind = "action", id = "settings", text = "⚙️ " .. i18n.t("menu_open_settings") }
    rows[#rows + 1] = { kind = "action", id = "logs", text = "📋 " .. i18n.t("menu_view_logs") }
    rows[#rows + 1] = { kind = "action", id = "dhcp", text = "🔄 " .. i18n.t("menu_update_dhcp") }
    rows[#rows + 1] = { kind = "action", id = "detect", text = "🔍 " .. i18n.t("menu_force_detect") }

    return {
        rows = rows,
        actions = {
            settings = function() ui.showEditor(config.current) end,
            logs = function()
                local f = io.open(logFilePath, "r")
                local content = ""
                if f then
                    content = f:read("*a")
                    f:close()
                end
                ui.showPopup("log", i18n.t("recent_system_logs"), content)
            end,
            dhcp = function() networkApply.setCurrentNetworkToDHCP() end,
            detect = function()
                utils.log(i18n.t("log_manual_detect"))
                currentSSID = nil
                invalidateStatusCache()
                M.performNetworkAudit()
            end
        }
    }
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
        
        local panelReady = USE_PANEL_MENU and panel.attach(M.menuBarItem, buildPanelModel)

        if panelReady then
            -- The self-drawn panel owns the item; there is no NSMenu to build.
        else
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
    
    -- Populate the status cache once at startup so the very first menu/panel
    -- open is instant, then keep it warm on a background timer. The timer means
    -- opening the status menu (which only reads the cache now) never blocks on
    -- the ~20 shell processes that build the network snapshot. With the Clash
    -- probes gated in core.lua, the periodic refresh is cheap when no proxy is
    -- running.
    refreshNetworkStatusCache(true)
    if M.statusTimer then pcall(function() M.statusTimer:stop() end) end
    M.statusTimer = timer.doEvery(STATUS_CACHE_TTL, function()
        refreshNetworkStatusCache(true)
    end)

    timer.doAfter(2, function()
        ui.syncHardwareStatusToUI()
    end)

    -- Tear down the panel webview, its event tap, and the timers on reload or
    -- shutdown so repeated "Reload Config" calls don't leak zombie windows or
    -- accumulate stale taps/timers from the previous module instance.
    hs.shutdownCallback = function()
        pcall(function() if M.statusTimer then M.statusTimer:stop() end end)
        pcall(panel.hide)
        pcall(panel.destroy)
    end

    utils.log(i18n.t("log_init_success"))
end

_G.WiFiAutoConfigModule = M
_G.WiFiAutoConfigModule.init()

return M
