-- ~/.hammerspoon/wifi_autoconfig/menu_builder.lua
local styledtext = require("hs.styledtext")
local i18n = require("wifi_autoconfig.i18n")

local M = {}

local DARK_MODE_TTL = 5
local cachedDarkMode = nil
local cachedDarkModeTime = 0

function M.detectDarkMode()
    local now = os.time()
    if cachedDarkMode ~= nil and (now - cachedDarkModeTime) < DARK_MODE_TTL then
        return cachedDarkMode
    end

    local handle = io.popen("defaults read -g AppleInterfaceStyle 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()
        cachedDarkMode = result:match("Dark") ~= nil
        cachedDarkModeTime = now
        return cachedDarkMode
    end

    return cachedDarkMode == true
end

function M.buildColors(isDarkMode)
    return {
        wifiHeader = isDarkMode and "#64B5F6" or "#002171",
        vpnHeader = isDarkMode and "#FFB74D" or "#8B2500",
        subsection = isDarkMode and "#90CAF9" or "#0D47A1",
        connected = isDarkMode and "#4CAF50" or "#1B5E20",
        disconnected = isDarkMode and "#FF7043" or "#B71C1C",
        normal = isDarkMode and "#FFFFFF" or "#000000",
        muted = isDarkMode and "#888888" or "#5E35B1",
        highlightBg = isDarkMode and "#333333" or "#E8E8E8",
        highlightFg = isDarkMode and "#FFFFFF" or "#000000"
    }
end

local function labelStyle(isDarkMode)
    return { color = { hex = isDarkMode and "#90CAF9" or "#1565C0" } }
end

local function valueStyle(isDarkMode)
    return { color = { hex = isDarkMode and "#E0E0E0" or "#333333" }, font = { size = 12 } }
end

local function mutedStyle(isDarkMode)
    return { color = { hex = isDarkMode and "#AAAAAA" or "#666666" }, font = { size = 11 } }
end

local function vpnStatusText(status)
    if status == "Connected" then
        return i18n.t("menu_status_connected")
    end
    return i18n.t("menu_status_disconnected")
end

function M.buildNetworkStatusMenuItems(cache)
    local items = {}
    local status = cache.wifiStatus or {}
    local ip, gw, nm = cache.ipv4.ip, cache.ipv4.gw, cache.ipv4.nm
    local v4mode = cache.ipv4.mode
    local v6mode, v6ip, v6prefix, v6gw = cache.ipv6.mode, cache.ipv6.ip, cache.ipv6.prefix, cache.ipv6.gw
    local activeDns = cache.dns
    local vpnInfo = cache.vpnInfo or {}
    local isDarkMode = cache.isDarkMode or false

    local colors = M.buildColors(isDarkMode)

    local wifiStatusText
    if status.powerState == "Off" then
        wifiStatusText = i18n.t("menu_status_disabled")
    elseif status.connected and status.ssid then
        wifiStatusText = i18n.t("menu_status_connected")
    else
        wifiStatusText = i18n.t("menu_status_disconnected")
    end

    table.insert(items, {
        title = styledtext.new(i18n.t("menu_status_wifi_header") .. " (" .. wifiStatusText .. ")",
            { color = { hex = colors.subsection }, font = { size = 13 } }),
        disabled = true
    })

    if status.connected and status.ssid then
        table.insert(items, {
            title = styledtext.new("  " .. i18n.t("menu_label_ssid") .. ":", labelStyle(isDarkMode))
                .. styledtext.new(" " .. status.ssid, valueStyle(isDarkMode)),
            disabled = true
        })
        table.insert(items, {
            title = styledtext.new("  " .. i18n.t("menu_label_ipv4") .. ": " .. tostring(v4mode), labelStyle(isDarkMode)),
            disabled = true
        })
        if ip and ip ~= "" then
            table.insert(items, {
                title = styledtext.new("    " .. i18n.t("menu_label_ip") .. ": " .. ip, valueStyle(isDarkMode)),
                disabled = true
            })
            if nm and nm ~= "" then
                table.insert(items, {
                    title = styledtext.new("    " .. i18n.t("menu_label_netmask") .. ": " .. nm, valueStyle(isDarkMode)),
                    disabled = true
                })
            end
            if gw and gw ~= "" then
                table.insert(items, {
                    title = styledtext.new("    " .. i18n.t("menu_label_gateway") .. ": " .. gw, valueStyle(isDarkMode)),
                    disabled = true
                })
            end
        end
        table.insert(items, {
            title = styledtext.new("  " .. i18n.t("menu_label_ipv6") .. ": " .. tostring(v6mode), labelStyle(isDarkMode)),
            disabled = true
        })
        if v6mode ~= i18n.t("v6_off") and v6ip and v6ip ~= i18n.t("unassigned") then
            table.insert(items, {
                title = styledtext.new("    " .. i18n.t("menu_label_ip") .. ": " .. v6ip, valueStyle(isDarkMode)),
                disabled = true
            })
            if v6prefix and v6prefix ~= "" then
                table.insert(items, {
                    title = styledtext.new("    " .. i18n.t("menu_label_prefix") .. ": /" .. v6prefix, valueStyle(isDarkMode)),
                    disabled = true
                })
            end
            if v6gw and v6gw ~= "" then
                table.insert(items, {
                    title = styledtext.new("    " .. i18n.t("menu_label_gateway") .. ": " .. v6gw, valueStyle(isDarkMode)),
                    disabled = true
                })
            end
        end
        table.insert(items, {
            title = styledtext.new("  " .. i18n.t("menu_label_dns") .. ":", labelStyle(isDarkMode))
                .. styledtext.new(" " .. tostring(activeDns), valueStyle(isDarkMode)),
            disabled = true
        })
    end

    if #vpnInfo > 0 then
        table.insert(items, { title = "-" })
        table.insert(items, {
            title = styledtext.new(i18n.t("menu_status_vpn_header"), { color = { hex = colors.vpnHeader }, font = { size = 13 } }),
            disabled = true
        })

        for _, v in ipairs(vpnInfo) do
            local statusColor = v.status == "Connected" and colors.connected or colors.disconnected

            local nameLine = string.format("  %s [%s] - %s", v.name, v.source, vpnStatusText(v.status))
            table.insert(items, {
                title = styledtext.new(nameLine, { color = { hex = statusColor }, font = { size = 12 } }),
                disabled = true
            })
            if v.interface then
                table.insert(items, {
                    title = styledtext.new("    " .. i18n.t("menu_status_vpn_interface") .. ": " .. v.interface, mutedStyle(isDarkMode)),
                    disabled = true
                })
            end
            if v.details and v.details.ip4 then
                table.insert(items, {
                    title = styledtext.new("    " .. i18n.t("menu_label_ipv4") .. ": " .. v.details.ip4, mutedStyle(isDarkMode)),
                    disabled = true
                })
            end
            if v.details and v.details.ip6 then
                table.insert(items, {
                    title = styledtext.new("    " .. i18n.t("menu_label_ipv6") .. ": " .. v.details.ip6, mutedStyle(isDarkMode)),
                    disabled = true
                })
            end
        end
    end

    table.insert(items, { title = "-" })
    return items
end

return M
