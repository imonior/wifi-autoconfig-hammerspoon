-- ~/.hammerspoon/wifi_autoconfig/menu_builder.lua
local styledtext = require("hs.styledtext")
local i18n = require("wifi_autoconfig.i18n")

local M = {}

-- The blue square (🟦) blue, sampled from the system emoji rendering. It is the
-- colour of every detail label in the menu (SSID, IPv4 mode, IPv6 mode, DNS ...).
local ACCENT_BLUE = "#055DF2"

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
    -- The menu panel keeps the macOS native (light grey) surface: hs.menubar
    -- exposes no API to tint it (libmenubar.m has no background/appearance
    -- handling at all), so legibility has to come from the text colours.
    return {
        -- Shared section-title colour, used by both the Wi-Fi status section and
        -- the VPN section so the two headers read as one family. It is the
        -- warning amber: bright on a dark surface, darkened to a gold that still
        -- clears ~3.5:1 against the light grey panel.
        sectionHeader = isDarkMode and "#FFD34E" or "#A67C00",
        -- Traffic-light status colours. Green is the only one that has to split
        -- by appearance: #00FF00 has a relative luminance above the light panel,
        -- so on the grey surface it washes out completely (~0.9:1). The darkened
        -- green keeps the green meaning while staying readable in light mode.
        connected = isDarkMode and "#00FF00" or "#008000",
        -- Pure red reads on both surfaces (~3.5:1 light), so it stays the
        -- traffic-light red in both appearances.
        disconnected = "#FF0000"
    }
end

local function labelStyle(isDarkMode)
    -- Detail labels (SSID, IPv4 mode, IPv6 mode, DNS ...) use the 🟦 blue.
    return { color = { hex = ACCENT_BLUE } }
end

-- Body text deliberately carries no explicit colour: it simply inherits the
-- menu's default foreground, which is exactly how the plain menu entries
-- (e.g. "View Logs") are drawn. Only the size separates the two levels.
local function valueStyle()
    return { font = { size = 12 } }
end

local function mutedStyle()
    return { font = { size = 11 } }
end

-- Traffic-light dot prefixed to the VPN status line: green when connected,
-- red when disconnected (mirrors the 🟢 / 🔴 status colours).
local function vpnStatusDot(status)
    return status == "Connected" and "🟢 " or "🔴 "
end

local function vpnStatusText(status)
    if status == "Connected" then
        return i18n.t("menu_status_connected")
    end
    return i18n.t("menu_status_disconnected")
end

-- The egress rows show whatever the probe timer last wrote, so the two states before an
-- address exists have to be told apart: no probe yet is normal (the panel must open
-- instantly and never wait on one), while a probe that ran and got nothing is the failure.
local function egressValueText(address, probed)
    if address and address ~= "" then return address end
    if probed then return i18n.t("menu_egress_failed") end
    return i18n.t("menu_egress_pending")
end

-- The row model is the single source of truth for what the status menu shows.
-- Two renderers consume it:
--   * panel.lua turns it into the self-drawn WebKit panel (the default UI),
--   * rowsToMenuItems() turns it into hs.menubar entries (the fallback path,
--     kept so the native menu can be restored with one flag in init.lua).
-- Kinds: head | kv | label | muted | status | sep.
function M.buildStatusRows(cache)
    local rows = {}
    local status = cache.wifiStatus or {}
    local ip, gw, nm = cache.ipv4.ip, cache.ipv4.gw, cache.ipv4.nm
    local v4mode = cache.ipv4.mode
    local v6mode, v6ip, v6prefix, v6gw = cache.ipv6.mode, cache.ipv6.ip, cache.ipv6.prefix, cache.ipv6.gw
    local activeDns = cache.dns
    local egress = cache.egress or {}
    local vpnInfo = cache.vpnInfo or {}

    local wifiStatusText
    if status.powerState == "Off" then
        wifiStatusText = i18n.t("menu_status_disabled")
    elseif status.connected and status.ssid then
        wifiStatusText = i18n.t("menu_status_connected")
    else
        wifiStatusText = i18n.t("menu_status_disconnected")
    end

    rows[#rows + 1] = {
        kind = "head",
        text = i18n.t("menu_status_wifi_header") .. " (" .. wifiStatusText .. ")"
    }

    if status.connected and status.ssid then
        rows[#rows + 1] = { kind = "kv", indent = 1, label = i18n.t("menu_label_ssid") .. ":", value = status.ssid }
        rows[#rows + 1] = { kind = "label", indent = 1, text = i18n.t("menu_label_ipv4") .. ": " .. tostring(v4mode) }
        if ip and ip ~= "" then
            rows[#rows + 1] = { kind = "muted", indent = 2, text = i18n.t("menu_label_ip") .. ": " .. ip }
            if nm and nm ~= "" then
                rows[#rows + 1] = { kind = "muted", indent = 2, text = i18n.t("menu_label_netmask") .. ": " .. nm }
            end
            if gw and gw ~= "" then
                rows[#rows + 1] = { kind = "muted", indent = 2, text = i18n.t("menu_label_gateway") .. ": " .. gw }
            end
        end
        rows[#rows + 1] = { kind = "label", indent = 1, text = i18n.t("menu_label_ipv6") .. ": " .. tostring(v6mode) }
        if v6mode ~= i18n.t("v6_off") and v6ip and v6ip ~= i18n.t("unassigned") then
            rows[#rows + 1] = { kind = "muted", indent = 2, text = i18n.t("menu_label_ip") .. ": " .. v6ip }
            if v6prefix and v6prefix ~= "" then
                rows[#rows + 1] = { kind = "muted", indent = 2, text = i18n.t("menu_label_prefix") .. ": /" .. v6prefix }
            end
            if v6gw and v6gw ~= "" then
                rows[#rows + 1] = { kind = "muted", indent = 2, text = i18n.t("menu_label_gateway") .. ": " .. v6gw }
            end
        end
        rows[#rows + 1] = { kind = "kv", indent = 1, label = i18n.t("menu_label_dns") .. ":", value = tostring(activeDns) }

        -- The address a peer sees, taken from the cache: the panel never waits on a probe.
        -- These two rows are the last of the current-Wi-Fi block - below DNS, above the
        -- VPN / virtual-NIC section - because they belong to the network below them.
        rows[#rows + 1] = {
            kind = "kv",
            indent = 1,
            label = i18n.t("menu_label_public_ip") .. ":",
            value = egressValueText(egress.direct, egress.probed)
        }
        -- Only while a system proxy is actually enabled, which is the one case where the
        -- address your traffic appears from is not the direct one.
        if egress.proxyURL then
            rows[#rows + 1] = {
                kind = "kv",
                indent = 1,
                label = i18n.t("menu_label_proxy_egress_ip") .. ":",
                value = egressValueText(egress.viaProxy, egress.probed)
            }
        end
    end

    if #vpnInfo > 0 then
        rows[#rows + 1] = { kind = "sep" }
        rows[#rows + 1] = { kind = "head", text = i18n.t("menu_status_vpn_header") }

        for _, v in ipairs(vpnInfo) do
            rows[#rows + 1] = {
                kind = "status",
                indent = 1,
                state = v.status == "Connected" and "ok" or "bad",
                -- The traffic-light dot is drawn by the renderer (a coloured
                -- emoji in the native fallback, a CSS dot in the panel).
                text = string.format("%s [%s] - %s", v.name, v.source, vpnStatusText(v.status))
            }
            if v.interface then
                rows[#rows + 1] = { kind = "muted", indent = 2, text = i18n.t("menu_status_vpn_interface") .. ": " .. v.interface }
            end
            if v.details and v.details.ip4 then
                -- The IPv4 gateway rides along the IPv4 line: IPv4/gateway: local>>peer
                local gw4 = v.route and v.route.gateway4 or nil
                -- Some tunnels (e.g. tun-mode proxies) use the same address for the
                -- local end and the peer, which carries no extra information.
                local usable = gw4 and gw4 ~= "" and not gw4:match("^link#") and gw4 ~= v.details.ip4
                local gw4Text = usable and (">>" .. gw4) or ""
                local egress4 = (v.status == "Connected" and v.defaultEgress4) and (" (" .. i18n.t("menu_vpn_default_egress") .. ")") or ""
                rows[#rows + 1] = {
                    kind = "muted",
                    indent = 2,
                    text = i18n.t("menu_label_ipv4_with_gw") .. ": " .. v.details.ip4 .. gw4Text .. egress4
                }
            end
            if v.details and v.details.ip6 then
                rows[#rows + 1] = { kind = "muted", indent = 2, text = i18n.t("menu_label_ipv6") .. ": " .. v.details.ip6 }
            end
            if v.route then
                -- Only show the IPv6 gateway when the interface actually has an IPv6 address,
                -- so the detail block mirrors whatever is listed above it.
                local gw6 = v.route.gateway6
                if gw6 and gw6 ~= "" and not gw6:match("^link#") and (v.details and v.details.ip6) then
                    -- Strip the interface scope (fe80::%utun3 -> fe80::); the interface is already listed above.
                    local gw6Text = gw6:gsub("%%%w+", "")
                    local egress6 = (v.status == "Connected" and v.defaultEgress6) and (" (" .. i18n.t("menu_vpn_default_egress") .. ")") or ""
                    rows[#rows + 1] = {
                        kind = "muted",
                        indent = 2,
                        text = i18n.t("menu_label_gateway") .. " (IPv6): " .. gw6Text .. egress6
                    }
                end
            end
            -- Which networks actually leave through this tunnel, one row per
            -- address family, listed after the addresses and gateways they route
            -- to. A full-tunnel VPN installs thousands of routes, so each row
            -- lists a few and gives the count for its own family; a family with
            -- no route of its own gets no row.
            local route = v.routeNetworks
            if route then
                for _, fam in ipairs({ {"v4", " (IPv4)"}, {"v6", " (IPv6)"} }) do
                    local info = route[fam[1]]
                    if info then
                        local shown = {}
                        for i = 1, math.min(3, #info.destinations) do
                            shown[#shown + 1] = info.destinations[i]
                        end
                        local more = info.count > #shown
                            and (" (" .. i18n.t("menu_vpn_routes_more"):format(info.count) .. ")") or ""
                        rows[#rows + 1] = {
                            kind = "muted",
                            indent = 2,
                            text = i18n.t("menu_label_route") .. fam[2] .. ": " .. table.concat(shown, ", ") .. more
                        }
                    end
                end
            end
        end
    end

    rows[#rows + 1] = { kind = "sep" }
    return rows
end

-- Native hs.menubar rendering of the row model. Unused while the self-drawn
-- panel is enabled; kept intact so the native menu stays one flag away.
local function rowsToMenuItems(rows, colors)
    local items = {}
    for _, r in ipairs(rows) do
        local pad = string.rep("  ", r.indent or 0)
        if r.kind == "sep" then
            items[#items + 1] = { title = "-" }
        elseif r.kind == "head" then
            items[#items + 1] = {
                title = styledtext.new(r.text, { color = { hex = colors.sectionHeader }, font = { size = 13 } })
            }
        elseif r.kind == "kv" then
            items[#items + 1] = {
                title = styledtext.new(pad .. r.label, labelStyle()) .. styledtext.new(" " .. r.value, valueStyle())
            }
        elseif r.kind == "label" then
            items[#items + 1] = { title = styledtext.new(pad .. r.text, labelStyle()) }
        elseif r.kind == "muted" then
            items[#items + 1] = { title = styledtext.new(pad .. r.text, mutedStyle()) }
        elseif r.kind == "status" then
            local c = (r.state == "ok") and colors.connected or colors.disconnected
            items[#items + 1] = {
                title = styledtext.new(pad .. vpnStatusDot(r.state == "ok" and "Connected" or "Disconnected") .. r.text,
                    { color = { hex = c }, font = { size = 12 } })
            }
        end
    end
    return items
end

function M.buildNetworkStatusMenuItems(cache)
    local colors = M.buildColors(cache.isDarkMode or false)
    return rowsToMenuItems(M.buildStatusRows(cache), colors)
end

return M
