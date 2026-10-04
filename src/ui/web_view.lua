-- ~/.hammerspoon/wifi_autoconfig/ui/web_view.lua
local webview = require("hs.webview")
local screen = require("hs.screen")
local urlevent = require("hs.urlevent")
local json = require("hs.json")
local drawing = require("hs.drawing")
local timer = require("hs.timer")
local core = require("wifi_autoconfig.core")
local utils = require("wifi_autoconfig.utils")
local config = require("wifi_autoconfig.config")
local i18n = require("wifi_autoconfig.i18n")

local M = {}
M.editorView = nil
M.popupView = nil
M.logPopupView = nil

local modulePath = utils.modulePath .. "ui/"

local templateCache = {}

local function loadTemplate(filename)
    if templateCache[filename] then
        return templateCache[filename]
    end
    local path = modulePath .. "templates/" .. filename
    local f = io.open(path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        templateCache[filename] = content
        return content
    else
        return nil
    end
end

-- 将 JSON 中的 < > 转义为 \u003c / \u003e，防止 </script> 穿透与脚本注入
local function escapeForInlineScript(s)
    return (s:gsub("[<>]", { ["<"] = "\\u003c", [">"] = "\\u003e" }))
end

-- Pre-load templates at module init time
loadTemplate("editor.html")
loadTemplate("popups.html")

function M.closeEditor()
    if M.editorView then
        M.editorView:delete()
        M.editorView = nil
    end
end

function M.showEditor(configData)
    -- 如果有老旧窗口，必须调用 delete 强行剔除底层 WebKit 引擎
    if M.editorView then 
        M.editorView:delete()
        M.editorView = nil 
    end
    
    local preferredNetworks = core.getPreferredNetworks()
    -- hs.json.encode returns nil instead of raising when a value cannot be encoded, and
    -- both strings below are spliced straight into the page (`let x = <json>;`). A nil
    -- here used to reach escapeForInlineScript() and raise, so opening the editor did
    -- nothing at all; an empty array/object is what the page expects for "no data".
    local networksJson = json.encode(preferredNetworks) or "[]"
    local configJson = json.encode(configData) or "{}"
    
    local html = loadTemplate("editor.html")
    if not html then return end

    html = html:gsub("%%NETWORKS_PLACEHOLDER%%", function() return escapeForInlineScript(networksJson) end)
    html = html:gsub("%%CONFIG_PLACEHOLDER%%", function() return escapeForInlineScript(configJson) end)
    html = html:gsub("%%LOCALE_PLACEHOLDER%%", function() return i18n.getLocale() end)

    local mainScreen = screen.mainScreen():frame()
    local w, h = 760, 580
    
    M.editorView = webview.new({
        x = mainScreen.x + (mainScreen.w - w) / 2,
        y = mainScreen.y + (mainScreen.h - h) / 2,
        w = w, h = h
    })
    
    -- 核心：当用户点击左上角红色叉叉关闭窗口时，必须彻底把变量和内存抹除干净
    M.editorView:windowCallback(function(action)
        if action == "closing" then
            utils.log(i18n.t("log_window_closed"))
            M.editorView = nil
        end
    end)
    
    M.editorView:html(html)
    M.editorView:windowTitle(i18n.t("app_name"))
    M.editorView:allowTextEntry(true)
    M.editorView:level(drawing.windowLevels.floating)
    
    if M.editorView.windowStyle then 
        M.editorView:windowStyle({"titled", "closable", "resizable", "miniaturizable"}) 
    end
    
    M.editorView:show()
    
    utils.log(i18n.t("log_window_created", tostring(M.editorView)))
    
    utils.waitForCondition(function()
        local status = core.getCurrentWiFiStatus()
        return status.ssid and status.ssid ~= ""
    end, 10, 0.5, function(ssidReady)
        if M.editorView then
            local status = core.getCurrentWiFiStatus()
            utils.log(i18n.t("log_delay_sync", tostring(status.ssid)))
            M.syncHardwareStatusToUI()
        end
    end)
end

function M.refreshEditor()
    utils.log(i18n.t("log_refresh_editor", tostring(M.editorView)))
    utils.log(i18n.t("log_refresh_editor_type", type(M.editorView)))
    
    if not M.editorView then 
        utils.log(i18n.t("log_refresh_nil"))
        return 
    end
    
    utils.log(i18n.t("log_refresh_content"))
    
    config.read()
    
    local preferredNetworks = core.getPreferredNetworks()
    -- Same as showEditor: an unencodable value must not reach refreshConfig(), whose
    -- JSON.parse('') would throw and leave the editor showing a stale list.
    local networksJson = json.encode(preferredNetworks) or "[]"
    local configJson = json.encode(config.current) or "{}"
    
    local configCount = 0
    for k,v in pairs(config.current) do configCount = configCount + 1 end
    utils.log(i18n.t("log_config_count", configCount))
    
    local jsExpr = string.format("refreshConfig('%s', '%s')", 
        utils.escapeJS(networksJson), utils.escapeJS(configJson))
    
    local success, result = pcall(function()
        return M.editorView:evaluateJavaScript(jsExpr)
    end)
    
    if success then
        utils.log(i18n.t("log_js_success"))
    else
        utils.log(i18n.t("log_js_fail", tostring(result)))
    end
    
    utils.wait(1, function()
        if M.editorView then
            M.syncHardwareStatusToUI()
        end
    end)
end

local syncLogCount = 0

function M.syncHardwareStatusToUI()
    if not M.editorView then return end
    
    local status = core.getCurrentWiFiStatus()
    local wifiInterface = core.getWiFiServiceName()
    -- Both address families come from one -getinfo call.
    local ip, gw, nm, v4mode, v6mode, v6ip = core.getCurrentIPInfo(wifiInterface)
    local dns = core.getActiveDNS()
    
    syncLogCount = syncLogCount + 1
    if syncLogCount % 5 == 0 then
        utils.log(i18n.t("log_sync_status", tostring(status.ssid), tostring(dns)))
    end
    
    local ssidStr = status.ssid or i18n.t("not_connected")
    local jsExpr = string.format("updateCurrentNetworkUI('%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s')", 
        utils.escapeJS(ssidStr), utils.escapeJS(v4mode), utils.escapeJS(ip), utils.escapeJS(nm), utils.escapeJS(gw), utils.escapeJS(dns), utils.escapeJS(v6mode), utils.escapeJS(v6ip))
        
    local success, result = pcall(function()
        return M.editorView:evaluateJavaScript(jsExpr)
    end)
    
    if not success then
        utils.log(i18n.t("log_sync_js_fail", tostring(result)))
    end
end

function M.showPopup(mode, title, contentPayload)
    local function createPopup()
        local html = loadTemplate("popups.html")
        if not html then return end

        html = html:gsub("%%POPUP_MODE%%", function() return mode end)
        html = html:gsub("%%POPUP_TITLE%%", function() return utils.escapeHTML(title) end)
        
        local escapedContent = utils.escapeHTML(contentPayload or "")
        html = html:gsub("%%POPUP_CONTENT%%", function() return escapedContent end)
        html = html:gsub("%%POPUP_TIME%%", function() return os.date("%Y-%m-%d %H:%M:%S") end)
        html = html:gsub("%%LOCALE_PLACEHOLDER%%", function() return i18n.getLocale() end)

        local mainScreen = screen.mainScreen():frame()
        local w, h = (mode == "log") and 600 or 340, (mode == "log") and 400 or 440

        local popup = webview.new({
            x = mainScreen.x + (mainScreen.w - w) / 2,
            y = mainScreen.y + (mainScreen.h - h) / 2,
            w = w, h = h
        }):html(html):windowTitle(title)
        
        if mode == "success" then
            popup:level(drawing.windowLevels.mainMenu + 1)
            M.popupView = popup
        else
            popup:level(drawing.windowLevels.floating)
            M.logPopupView = popup
        end

        if popup.windowStyle then popup:windowStyle({"titled", "closable", "resizable"}) end
        popup:show()
        
        utils.log(i18n.t("log_show_popup", tostring(title)))
    end

    if mode == "success" then
        if M.popupView and type(M.popupView) == "userdata" then
            pcall(function() M.popupView:delete() end)
            M.popupView = nil
            utils.log(i18n.t("log_close_old_popup"))
            timer.doAfter(0.1, createPopup)
            return
        end
    else
        if M.logPopupView and type(M.logPopupView) == "userdata" then
            pcall(function() M.logPopupView:delete() end)
            M.logPopupView = nil
            utils.log(i18n.t("log_close_log_popup"))
            timer.doAfter(0.1, createPopup)
            return
        end
    end
    
    createPopup()
end

urlevent.bind("close_popup_view", function() 
    if M.popupView and type(M.popupView) == "userdata" then 
        pcall(function() M.popupView:delete() end)
        M.popupView = nil 
    end 
    if M.logPopupView and type(M.logPopupView) == "userdata" then
        pcall(function() M.logPopupView:delete() end)
        M.logPopupView = nil
    end
end)

urlevent.bind("clear_log", function()
    local f = io.open(utils.logFilePath, "w")
    if f then
        f:close()
        utils.log(i18n.t("log_cleared"))
    end
    if M.logPopupView then
        local html = loadTemplate("popups.html")
        if html then
            html = html:gsub("%%POPUP_MODE%%", function() return "log" end)
            html = html:gsub("%%POPUP_TITLE%%", function() return i18n.t("recent_system_logs") end)
            html = html:gsub("%%POPUP_CONTENT%%", function() return "" end)
            html = html:gsub("%%POPUP_TIME%%", function() return os.date("%Y-%m-%d %H:%M:%S") end)
            html = html:gsub("%%LOCALE_PLACEHOLDER%%", function() return i18n.getLocale() end)
            M.logPopupView:html(html)
        end
    end
end)

urlevent.bind("refresh_log", function()
    local f = io.open(utils.logFilePath, "r")
    local content = ""
    if f then
        content = f:read("*a")
        f:close()
    end
    if M.logPopupView then
        local html = loadTemplate("popups.html")
        if html then
            html = html:gsub("%%POPUP_MODE%%", function() return "log" end)
            html = html:gsub("%%POPUP_TITLE%%", function() return i18n.t("recent_system_logs") end)
            html = html:gsub("%%POPUP_CONTENT%%", function() return utils.escapeHTML(content) end)
            html = html:gsub("%%POPUP_TIME%%", function() return os.date("%Y-%m-%d %H:%M:%S") end)
            html = html:gsub("%%LOCALE_PLACEHOLDER%%", function() return i18n.getLocale() end)
            M.logPopupView:html(html)
        end
    end
end)

return M