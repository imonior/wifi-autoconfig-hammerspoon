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

-- Keep in step with MODULE_VERSION in scripts/install.sh, which is the value the
-- release package name, the installer banner and the git tag are built from.
M.VERSION = "3.2.1"

-- The status list is drawn by panel.lua on its own dark surface. Set this to
-- false to go back to the native hs.menubar menu: it keeps the system menu
-- material (light grey in light appearance), which is what made the amber and
-- the green unreadable, and it cannot stop informational rows from lighting up
-- on hover.
local USE_PANEL_MENU = true

local modulePath = utils.modulePath
local logFilePath = utils.logFilePath

-- The SSID whose policy is known to be on the interface right now. This is a
-- confirmation, not an intention: it only moves once an apply sequence reports that
-- every step took effect.
local currentSSID = nil

-- What an apply sequence is busy with while it is still in flight or waiting for a
-- retry, how many retries that target has already spent, and the retry timer.
local applyTarget = nil
local applyAttempts = 0
local applyRetryTimer = nil

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
    -- The service name / hardware device are cached inside core.lua, and a
    -- network change is exactly when they may be wrong (renamed service,
    -- external dongle attached). Drop them too so the next read re-resolves.
    core.invalidateInterfaceCache()
end

local function stopApplyRetry()
    if applyRetryTimer then
        pcall(function() applyRetryTimer:stop() end)
        applyRetryTimer = nil
    end
end

-- An apply that ended with a failing step is not a finished job, and the reasons are
-- mostly temporary: the interface had not finished associating after wake, the lease
-- had not arrived yet, the sudoers rule was added a minute later, config.json was
-- still being repaired. Waiting for the SSID to change would leave the network in the
-- half-applied state until the user happened to reconnect, so the audit runs again on
-- a timer. The cap exists because a permanently broken setup (no rule at all, a policy
-- that will not parse) must not knock on networksetup forever.
local APPLY_RETRY_DELAY = 60
local APPLY_RETRY_LIMIT = 5

local runApplySequence

local function scheduleApplyRetry(ssid)
    stopApplyRetry()
    if applyAttempts >= APPLY_RETRY_LIMIT then
        utils.log(i18n.t("log_apply_gave_up", ssid, APPLY_RETRY_LIMIT))
        applyTarget = nil
        applyAttempts = 0
        return
    end
    applyAttempts = applyAttempts + 1
    utils.log(i18n.t("log_apply_retry_scheduled", ssid, applyAttempts, APPLY_RETRY_DELAY))
    -- The claim stays with this SSID for the whole wait: it is what makes a repeated
    -- watcher event a no-op instead of a second concurrent sequence.
    applyRetryTimer = timer.doAfter(APPLY_RETRY_DELAY, function()
        applyRetryTimer = nil
        if applyTarget ~= ssid then return end

        local status = core.getCurrentWiFiStatus()
        if not status.connected or status.ssid ~= ssid then
            -- The association we were fixing is gone (or became a different network) while
            -- the timer waited, so this retry budget belongs to nothing.
            currentSSID = nil
            applyTarget = nil
            applyAttempts = 0
            return
        end

        -- applyTarget still holds ssid, which is what keeps the retry budget intact:
        -- runApplySequence() is entered directly rather than through the audit, and only
        -- the audit resets the count.
        runApplySequence(ssid)
    end)
end

function runApplySequence(ssid)
    stopApplyRetry()
    applyTarget = ssid

    utils.log(i18n.t("log_ssid_change", tostring(currentSSID), ssid))
    invalidateStatusCache()

    config.read()
    networkApply.applyNetworkStrategy(ssid, function(applied)
        -- Only the sequence that still owns this SSID may confirm it. Once another
        -- network has taken over, that one reports its own outcome.
        if applyTarget ~= ssid then return end
        if applied then
            applyTarget = nil
            applyAttempts = 0
            currentSSID = ssid
        else
            scheduleApplyRetry(ssid)
        end
    end)
end

function M.performNetworkAudit()
    local status = core.getCurrentWiFiStatus()
    if not status.connected or not status.ssid then
        utils.log(i18n.t("log_wifi_sleep"))
        -- Forget what was applied. The network that comes back is a new one as far as
        -- this module is concerned even when it carries the same SSID: the lease can
        -- have been lost with the association, and an address can have been dropped by
        -- sleep, a VPN, or the step that failed before the link went down. Leaving the
        -- name set would make the next watcher event for the same SSID compare equal
        -- and return, so a reconnect would never be re-audited.
        stopApplyRetry()
        applyTarget = nil
        applyAttempts = 0
        currentSSID = nil
        return
    end

    local ssid = status.ssid
    if ssid == currentSSID then
        return
    end

    -- A sequence is already running for this SSID or is waiting to retry it. Starting
    -- another would supersede the one in flight and duplicate the report.
    if ssid == applyTarget then
        return
    end

    -- A different network takes over: its retry budget starts from zero.
    applyAttempts = 0
    runApplySequence(ssid)
end

local function refreshNetworkStatusCache(force)
    if not force and isCacheFresh() then
        return
    end

    cachedNetworkStatus.wifiStatus = core.getCurrentWiFiStatus()
    cachedNetworkStatus.wifiInterface = core.getWiFiServiceName()

    -- One `networksetup -getinfo` covers both address families.
    local ip, gw, nm, v4mode, v6mode, v6ip, v6prefix, v6gw =
        core.getCurrentIPInfo(cachedNetworkStatus.wifiInterface)
    cachedNetworkStatus.ipv4 = { ip = ip, gw = gw, nm = nm, mode = v4mode }
    cachedNetworkStatus.ipv6 = { mode = v6mode, ip = v6ip, prefix = v6prefix, gw = v6gw }

    cachedNetworkStatus.dns = core.getActiveDNS()
    cachedNetworkStatus.vpnInfo = core.getVPNInfo()
    cachedNetworkStatus.isDarkMode = menuBuilder.detectDarkMode()

    cacheTimestamp = os.time()
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

    -- Validate before the confirmation dialog, not after: everything below
    -- this point runs `sudo /usr/sbin/networksetup` under a NOPASSWD sudoers
    -- rule, so a malformed IP/netmask/gateway would be pushed straight into
    -- the live network configuration with no prompt and no rollback.
    local valid, errMsg = config.validateConfig(data)
    if not valid then
        dialog.showAlert(i18n.t("ui_validation_error") .. ": " .. errMsg)
        utils.log(i18n.t("log_validation_failed", tostring(data.ssid), errMsg))
        return
    end

    utils.log(i18n.t("log_force_apply_with_data", json.encode(data)))

    local choice = utils.blockAlertOnce(
        i18n.t("popup_title_confirm_force_apply"),
        buildConfigSummary(data),
        i18n.t("popup_confirm"),
        i18n.t("popup_cancel")
    )

    if choice ~= i18n.t("popup_confirm") then
        return
    end

    -- A forced override replaces whatever the automatic path was doing with this
    -- network: applyConfigToInterface() without a token takes a new run generation, which
    -- retires the sequence in flight, so the bookkeeping has to be cleared too or the
    -- SSID would stay claimed by a sequence that can no longer report.
    stopApplyRetry()
    applyTarget = nil
    applyAttempts = 0
    invalidateStatusCache()

    networkApply.applyConfigToInterface(wifiInterface, data, function(problems)
        -- Same rule as the automatic path: the network counts as handled only once every
        -- step landed. Otherwise a later watcher event re-audits it instead of being
        -- swallowed by a name that was committed before the first command ran.
        if not problems or #problems == 0 then
            currentSSID = data.ssid
        else
            currentSSID = nil
        end

        utils.wait(2, function()
            local report = networkApply.buildNetworkReport(i18n.t("config_source_editor"))
            ui.showPopup("success", networkApply.resultTitle(problems, i18n.t("popup_title_force_apply_success")),
                networkApply.withProblems(problems, report))
            ui.syncHardwareStatusToUI()
        end)
    end)
end

-- Shared by the panel row and the native menu item, so the two commands cannot drift.
local function forceRedetect()
    utils.log(i18n.t("log_manual_detect"))
    -- "Force detect" means re-audit even the network this module is already working on,
    -- so the claim a running or waiting sequence holds has to be dropped first;
    -- otherwise the audit below returns at the applyTarget check and the click does
    -- nothing.
    stopApplyRetry()
    applyTarget = nil
    applyAttempts = 0
    currentSSID = nil
    invalidateStatusCache()
    M.performNetworkAudit()
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
            detect = forceRedetect
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
                    fn = forceRedetect
                })
            
                return menuItems
            end)
        end
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
        stopApplyRetry()
        pcall(panel.hide)
        pcall(panel.destroy)
    end

    utils.log(i18n.t("log_init_success"))
end

_G.WiFiAutoConfigModule = M
_G.WiFiAutoConfigModule.init()

return M
