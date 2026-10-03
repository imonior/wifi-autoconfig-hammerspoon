local notify = require("hs.notify")
local core = require("wifi_autoconfig.core")
local config = require("wifi_autoconfig.config")
local utils = require("wifi_autoconfig.utils")
local ui = require("wifi_autoconfig.ui.web_view")
local i18n = require("wifi_autoconfig.i18n")

local M = {}

function M.buildNetworkReport(configSource, cachedStatus)
    local status = cachedStatus or core.getCurrentWiFiStatus()
    local ssid = status.ssid or i18n.t("unknown")
    local wifiInterface = core.getWiFiServiceName()
    local wifiDevice = core.getWiFiDevice()
    local ip, gw, nm, v4mode = core.getCurrentIPv4Info(wifiInterface)
    local activeDns = core.getActiveDNS()
    local v6mode, v6ip, v6prefix, v6gw = core.getCurrentIPv6Info(wifiInterface)

    local report = i18n.t("label_ssid") .. ": " .. ssid .. "\n" ..
        i18n.t("label_config_source") .. ": " .. configSource .. "\n\n" ..
        i18n.t("label_ipv4") .. "\n" ..
        i18n.t("label_mode") .. ": " .. v4mode .. "\n" ..
        i18n.t("label_address") .. ": " .. ip .. "\n" ..
        i18n.t("label_netmask") .. ": " .. nm .. "\n" ..
        i18n.t("label_gateway") .. ": " .. gw .. "\n\n" ..
        i18n.t("label_ipv6") .. "\n" ..
        i18n.t("label_mode") .. ": " .. v6mode .. "\n" ..
        i18n.t("label_address") .. ": " .. v6ip .. "\n" ..
        (v6prefix ~= "" and (i18n.t("menu_label_prefix") .. ": " .. v6prefix .. "\n") or "") ..
        (v6gw ~= "" and (i18n.t("label_gateway") .. ": " .. v6gw .. "\n") or "") ..
        "\n" ..
        i18n.t("label_dns") .. "\n" ..
        activeDns .. "\n\n" ..
        i18n.t("label_system") .. "\n" ..
        i18n.t("label_interface") .. ": " .. wifiInterface .. "\n" ..
        i18n.t("label_device") .. ": " .. wifiDevice
    return report, ssid
end

function M.showNetworkReport(ssid)
    local status = core.getCurrentWiFiStatus()
    local currentSSID = status.ssid or i18n.t("unknown")

    if currentSSID ~= ssid then
        utils.log(i18n.t("log_ssid_changed", ssid, currentSSID))
        ssid = currentSSID
    end

    local hasCustomConfig = config.current[ssid] ~= nil
    local hasGlobalConfig = config.current["__DEFAULT__"] ~= nil

    local configSource
    if hasCustomConfig then
        configSource = i18n.t("config_source_custom")
    elseif hasGlobalConfig then
        configSource = i18n.t("config_source_global")
    else
        configSource = i18n.t("config_source_dhcp")
    end

    local report = M.buildNetworkReport(configSource, status)
    ui.showPopup("success", i18n.t("popup_title_config_success"), report)
    ui.syncHardwareStatusToUI()
end

function M.applyConfigToInterface(wifiInterface, setting, callback)
    if setting.mode == "manual" then
        local netmask = setting.netmask or "255.255.255.0"
        
        core.configureIPv6(wifiInterface, setting.v6mode, setting.ipv6, setting.v6prefix, setting.v6gateway)
        
        core.runWithSudo("/usr/sbin/networksetup -setmanual " .. core.shellQuote(wifiInterface) .. " " .. core.shellQuote(setting.ip) .. " " .. core.shellQuote(netmask) .. " " .. core.shellQuote(setting.gateway))
        
        utils.waitForCondition(function()
            local currentIp, _, _ = core.getCurrentIPv4Info(wifiInterface)
            return currentIp == setting.ip
        end, 10, 0.5, function(ipSet)
            if not ipSet then utils.log(i18n.t("log_warn_ip_not_effective")) end
            
            core.setDNSServers(wifiInterface, setting.dns)
            
            local targetDns = setting.dns or ""
            if targetDns:match("%S") then
                utils.waitForCondition(function()
                    local activeDns = core.getActiveDNS()
                    local activeSet = {}
                    for entry in string.gmatch(activeDns, "[^,%s]+") do activeSet[entry] = true end
                    for dnsEntry in string.gmatch(targetDns, "[^,%s]+") do
                        if not activeSet[dnsEntry] then
                            return false
                        end
                    end
                    return true
                end, 5, 0.5, function(dnsSet)
                    if not dnsSet then utils.log(i18n.t("log_warn_dns_not_effective")) end
                    if callback then callback() end
                end)
            else
                if callback then callback() end
            end
        end)
    else
        core.runWithSudo("/usr/sbin/networksetup -setdhcp " .. core.shellQuote(wifiInterface))
        
        utils.waitForCondition(function()
            local currentIp, _, _ = core.getCurrentIPv4Info(wifiInterface)
            return currentIp ~= "" and currentIp ~= "0.0.0.0"
        end, 15, 0.5, function(ipObtained)
            if not ipObtained then utils.log(i18n.t("log_warn_no_dhcp")) end
            
            core.configureIPv6(wifiInterface, setting.v6mode, setting.ipv6, setting.v6prefix, setting.v6gateway)
            
            local targetDns = setting.dns or ""
            if targetDns and tostring(targetDns):match("%S") then
                core.setDNSServers(wifiInterface, targetDns)
            else
                core.setDNSServers(wifiInterface, "")
            end
            
            if callback then callback() end
        end)
    end
end

function M.applyNetworkStrategy(ssid)
    local wifiInterface = core.getWiFiServiceName()
    local setting = config.current[ssid]

    if not setting then
        setting = config.current["__DEFAULT__"]
    end

    if setting then
        utils.log(i18n.t("log_apply_rule", ssid, setting.mode))
        
        M.applyConfigToInterface(wifiInterface, setting, function()
            if setting.mode == "manual" then
                notify.new({title=i18n.t("notify_title_config_changed"), informativeText="SSID: "..ssid.."\n"..i18n.t("notify_static_ip")}):send()
            else
                notify.new({title=i18n.t("notify_title_config_changed"), informativeText="SSID: "..ssid.."\n"..i18n.t("notify_dhcp")}):send()
            end
            utils.wait(1, function()
                M.showNetworkReport(ssid)
            end)
        end)
    else
        utils.log(i18n.t("log_no_config_fallback"))
        core.runWithSudo("/usr/sbin/networksetup -setdhcp " .. core.shellQuote(wifiInterface))
        
        utils.waitForCondition(function()
            local currentIp, _, _ = core.getCurrentIPv4Info(wifiInterface)
            return currentIp ~= "" and currentIp ~= "0.0.0.0"
        end, 15, 0.5, function(ipObtained)
            if not ipObtained then utils.log(i18n.t("log_warn_no_dhcp")) end
            
            core.setDNSServers(wifiInterface, "")
            
            notify.new({title=i18n.t("notify_title_config_changed"), informativeText="SSID: "..ssid.."\n"..i18n.t("notify_dhcp")}):send()
            utils.wait(1, function()
                M.showNetworkReport(ssid)
            end)
        end)
    end
end

function M.setCurrentNetworkToDHCP()
    local wifiInterface = core.getWiFiServiceName()
    utils.log(i18n.t("log_manual_dhcp"))
    
    core.runWithSudo("/usr/sbin/networksetup -setdhcp " .. core.shellQuote(wifiInterface))
    core.configureIPv6(wifiInterface, "automatic", "", "", "")
    
    utils.waitForCondition(function()
        local currentIp, _, _ = core.getCurrentIPv4Info(wifiInterface)
        return currentIp ~= "" and currentIp ~= "0.0.0.0"
    end, 15, 0.5, function(ipObtained)
        if not ipObtained then utils.log(i18n.t("log_warn_no_dhcp")) end
        
        core.setDNSServers(wifiInterface, "")

        utils.wait(1, function()
            local report = M.buildNetworkReport(i18n.t("config_source_dhcp"))
            ui.showPopup("success", i18n.t("popup_title_dhcp_success"), report)
            ui.syncHardwareStatusToUI()
        end)
    end)
end

return M