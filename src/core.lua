-- ~/.hammerspoon/wifi_autoconfig/core.lua
local wifi = require("hs.wifi")
local utils = require("wifi_autoconfig.utils")
local i18n = require("wifi_autoconfig.i18n")

local M = {}

local cachedWiFiServiceName = nil
local cachedWiFiDevice = nil

local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

M.shellQuote = shellQuote

function M.runWithSudo(cmd)
    local fullCmd = string.format("sudo %s", cmd)
    utils.log(i18n.t("log_cmd_exec", fullCmd))
    
    local handle = io.popen(fullCmd .. " 2>&1")
    if not handle then
        utils.log(i18n.t("log_cmd_open_fail"))
        return false, i18n.t("log_cmd_open_fail")
    end
    
    local result = handle:read("*a")
    local success, _, exitCode = handle:close()
    
    utils.log(i18n.t("log_cmd_output", result or ""))
    
    local ok = (exitCode == 0)
    if not ok then
        utils.log(i18n.t("log_cmd_failed", fullCmd))
        utils.log(i18n.t("log_cmd_error", result or ""))
    end
    return ok, result
end

function M.getWiFiServiceName()
    if cachedWiFiServiceName then return cachedWiFiServiceName end
    local handle = io.popen('/usr/sbin/networksetup -listallnetworkservices')
    if not handle then return "Wi-Fi" end
    local result = handle:read("*a")
    handle:close()
    for line in result:gmatch("[^\r\n]+") do
        if line:match("Wi%-Fi") or line:match("无线网络") then 
            cachedWiFiServiceName = line
            return line 
        end
    end
    cachedWiFiServiceName = "Wi-Fi"
    return "Wi-Fi"
end

function M.getWiFiDevice()
    if cachedWiFiDevice then return cachedWiFiDevice end
    local handle = io.popen("/usr/sbin/networksetup -listallhardwareports")
    if not handle then return "en0" end
    local result = handle:read("*a")
    handle:close()
    for port, dev in result:gmatch("Hardware Port:%s*([^\n]+)%s*\nDevice:%s*([^\n]+)") do
        if port and port:match("Wi%-Fi") then 
            cachedWiFiDevice = dev:match("^%s*(.-)%s*$")
            return cachedWiFiDevice 
        end
    end
    cachedWiFiDevice = "en0"
    return "en0"
end

function M.getPreferredNetworks()
    local networks = {}
    local dev = M.getWiFiDevice()
    local handle = io.popen("/usr/sbin/networksetup -listpreferredwirelessnetworks " .. shellQuote(dev))
    if handle then
        local result = handle:read("*a")
        handle:close()
        local isFirst = true
        for line in result:gmatch("[^\r\n]+") do
            if isFirst then isFirst = false else
                local ssid = line:match("^%s*(.-)%s*$")
                if ssid and ssid ~= "" then table.insert(networks, ssid) end
            end
        end
    end
    return networks
end

function M.getCurrentWiFiStatus()
    local status = {connected = false, ssid = nil, powerState = nil}
    
    -- Check WiFi power state
    local wifiDevice = M.getWiFiDevice() or "en0"
    local ph = io.popen("/usr/sbin/networksetup -getairportpower " .. shellQuote(wifiDevice))
    if ph then
        local powerResult = ph:read("*a")
        ph:close()
        if powerResult:match("Off") then
            status.powerState = "Off"
        else
            status.powerState = "On"
        end
    end
    
    local wifiSSID = wifi.currentNetwork()
    if wifiSSID then
        status.connected = true
        status.ssid = wifiSSID
    else
        local interface = M.getWiFiDevice() or "en0"
        local cmd = "/usr/sbin/networksetup -getairportnetwork " .. shellQuote(interface)
        
        local handle = io.popen(cmd)
        if handle then
            local result = handle:read("*a")
            handle:close()
            
            for line in result:gmatch("[^\r\n]+") do
                local ssid = line:match("^Current Wi%-Fi Network: (.+)$")
                if ssid and ssid ~= "" then
                    status.connected = true
                    status.ssid = ssid
                    break
                end
            end
        end
    end
    
    if status.connected and status.ssid then
        local details = wifi.interfaceDetails()
        if details and details.ssid and not status.ssid then
            status.ssid = details.ssid
        end
    end

    return status
end

function M.getCurrentIPv4Info(wifiInterface)
    local handle = io.popen("/usr/sbin/networksetup -getinfo " .. shellQuote(wifiInterface))
    if not handle then return "", "", "", "" end
    local result = handle:read("*a")
    handle:close()

    local v4mode = i18n.t("v4_dhcp")
    if result:match("Manual Configuration") then v4mode = i18n.t("v4_manual") end

    return result:match("IP address:%s*([%d%.]+)") or "", result:match("Router:%s*([%d%.]+)") or "", result:match("Subnet mask:%s*([%d%.]+)") or "", v4mode
end

-- 【新增】解析 IPv6 生效状态与实际分配到的全球单播地址
function M.getCurrentIPv6Info(wifiInterface)
    local handle = io.popen("/usr/sbin/networksetup -getinfo " .. shellQuote(wifiInterface))
    if not handle then return i18n.t("v6_off"), i18n.t("unassigned"), "", "" end
    local result = handle:read("*a")
    handle:close()

    local v6mode = i18n.t("v6_off")
    if result:match("IPv6:.*Automatic") then v6mode = i18n.t("v6_automatic")
    elseif result:match("IPv6:.*Manual") then v6mode = i18n.t("v6_manual")
    elseif result:match("IPv6:.*Link") then v6mode = i18n.t("v6_link_local")
    elseif result:match("IPv6:.*Off") then v6mode = i18n.t("v6_off")
    elseif result:match("IPv6:.*Enabled") then v6mode = i18n.t("v6_enabled") end

    local v6ip = result:match("IPv6 IP address:%s*([%a%d%:]+)") or i18n.t("unassigned")
    local v6prefix = result:match("IPv6 prefix length:%s*(%d+)") or ""
    local v6router = result:match("IPv6 Router:%s*([%a%d%:]+)") or ""

    -- Only try ifconfig fallback if IPv6 is not Off
    if v6mode ~= i18n.t("v6_off") and v6ip == i18n.t("unassigned") then
        local dev = M.getWiFiDevice()
        local ih = io.popen(string.format("ifconfig %s", dev))
        if ih then
            local iconf = ih:read("*a")
            ih:close()
            for ip6, plen in iconf:gmatch("inet6%s+([%a%d%:]+)%s+prefixlen%s+(%d+)") do
                if not ip6:match("^fe80") and not ip6:match("^::1") then
                    v6ip = ip6
                    v6prefix = plen
                    break
                end
            end
        end
    end
    
    -- If IPv6 is Off, show "Off" not "unassigned"
    if v6mode == i18n.t("v6_off") then
        v6ip = i18n.t("v6_off")
    end
    return v6mode, v6ip, v6prefix, v6router
end

function M.getActiveDNS()
    local wifiInterface = M.getWiFiServiceName()
    local handle = io.popen("/usr/sbin/networksetup -getdnsservers " .. shellQuote(wifiInterface))
    if not handle then return i18n.t("system_auto") end
    local result = handle:read("*a")
    handle:close()

    local dnsList = {}
    for line in result:gmatch("[^\r\n]+") do
        local ip = line:match("^%s*(.-)%s*$")
        if ip and ip ~= "" and not ip:match("There aren't") then
            table.insert(dnsList, ip)
        end
    end

    if #dnsList == 0 then
        local rf = io.open("/etc/resolv.conf", "r")
        if rf then
            for line in rf:lines() do
                local ip = line:match("^nameserver%s+(.+)$")
                if ip then table.insert(dnsList, ip) end
            end
            rf:close()
        end
    end
    return #dnsList > 0 and table.concat(dnsList, ", ") or i18n.t("system_auto")
end

function M.setDNSServers(wifiInterface, dns)
    if dns and dns:match("%S") then
        local dnsList = {}
        for dnsEntry in string.gmatch(dns, "[^,%s]+") do table.insert(dnsList, shellQuote(dnsEntry)) end
        return M.runWithSudo("/usr/sbin/networksetup -setdnsservers " .. shellQuote(wifiInterface) .. " " .. table.concat(dnsList, " "))
    else
        return M.runWithSudo("/usr/sbin/networksetup -setdnsservers " .. shellQuote(wifiInterface) .. " empty")
    end
end

local function hexNetmaskToDotted(hex)
    if not hex then return "" end
    local n = tonumber(hex, 16)
    if not n then return "" end
    return string.format("%d.%d.%d.%d", 
        math.floor(n / 0x1000000) % 256,
        math.floor(n / 0x10000) % 256,
        math.floor(n / 0x100) % 256,
        n % 256)
end

local function getInterfaceDetails(wifiDevice)
    local ifaceDetails = {}
    local handle = io.popen("/sbin/ifconfig 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()

        local currentInterface = nil
        for line in result:gmatch("[^\r\n]+") do
            local name = line:match("^(%w[%w%d]+):")
            if name then
                currentInterface = name
                ifaceDetails[name] = { name = name, ip4 = nil, netmask4 = nil, ip6 = nil, prefix6 = nil, hasIPv4 = false, hasIPv6 = false }
            elseif currentInterface and ifaceDetails[currentInterface] then
                local inet = line:match("inet (%d+%.%d+%.%d+%.%d+)")
                if inet and inet ~= "127.0.0.1" then
                    ifaceDetails[currentInterface].ip4 = inet
                    ifaceDetails[currentInterface].hasIPv4 = true
                    local nmHex = line:match("netmask (%x+)")
                    if nmHex then
                        ifaceDetails[currentInterface].netmask4 = hexNetmaskToDotted(nmHex)
                    end
                end
                local inet6 = line:match("inet6 (%S+)%s+prefixlen%s+(%d+)")
                if inet6 and not inet6:match("^fe80") and not inet6:match("^::1") then
                    if not ifaceDetails[currentInterface].ip6 then
                        ifaceDetails[currentInterface].ip6 = inet6
                        ifaceDetails[currentInterface].prefix6 = line:match("prefixlen%s+(%d+)")
                        ifaceDetails[currentInterface].hasIPv6 = true
                    end
                end
            end
        end
    end

    ifaceDetails[wifiDevice] = nil
    ifaceDetails["lo0"] = nil
    return ifaceDetails
end

local function getRunningProcesses()
    local handle = io.popen("/bin/ps -axo comm= 2>/dev/null")
    if not handle then return "" end
    local result = handle:read("*a")
    handle:close()
    return result
end

local function getSystemVPNs(ifaceDetails, processList)
    local scutilVPNs = {}
    local handle = io.popen("/usr/sbin/scutil --nc list 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()

        for line in result:gmatch("[^\r\n]+") do
            local serviceName, serviceType = line:match('%*?%s*%([^)]*%).-"(.+)"%s+%[(.-)%]')
            if serviceName then
                local sh = io.popen("/usr/sbin/scutil --nc status " .. shellQuote(serviceName) .. " 2>/dev/null")
                local status = "Disconnected"
                local iface = nil
                if sh then
                    local statusResult = sh:read("*a")
                    sh:close()
                    local firstLine = statusResult:match("^[^\n]+")
                    if firstLine then
                        firstLine = firstLine:gsub("^%s+", ""):gsub("%s+$", "")
                        if firstLine == "Connected" then
                            status = "Connected"
                        elseif firstLine == "Disconnected" then
                            status = "Disconnected"
                        end
                    end
                    iface = statusResult:match("interface%s*:%s*(%w+)")
                    if not iface then
                        iface = statusResult:match("InterfaceName%s*:%s*(%w+)")
                    end
                end

                local details = nil
                if iface and ifaceDetails[iface] then
                    details = ifaceDetails[iface]
                    ifaceDetails[iface] = nil
                end

                local displayName = serviceName
                local vpnSource = "macOS VPN"

                if serviceName:lower():match("hiddify") or (serviceType and serviceType:lower():match("hiddify")) then
                    displayName = "Hiddify"
                    vpnSource = "Hiddify"
                elseif serviceName:lower():match("protonvpn") or serviceName:lower():match("proton vpn") then
                    displayName = "ProtonVPN"
                    vpnSource = "ProtonVPN"
                end

                table.insert(scutilVPNs, {
                    name = displayName,
                    type = serviceType,
                    status = status,
                    interface = iface,
                    details = details,
                    source = vpnSource
                })
            end
        end
    end
    return scutilVPNs
end

local function getWireGuardInterfaceMap()
    local wgInterfaceMap = {}
    local wgDir = "/var/run/wireguard/"
    local wgConfigNames = {}
    local wgIfaces = {}

    local nameHandle = io.popen("ls " .. wgDir .. "*.name 2>/dev/null")
    if nameHandle then
        for line in nameHandle:lines() do
            local configName = line:match("([^/]+)%.name$")
            if configName then
                table.insert(wgConfigNames, configName)
            end
        end
        nameHandle:close()
    end

    local sockHandle = io.popen("ls " .. wgDir .. "*.sock 2>/dev/null")
    if sockHandle then
        for line in sockHandle:lines() do
            local iface = line:match("(%w+)%.sock$")
            if iface then
                table.insert(wgIfaces, iface)
            end
        end
        sockHandle:close()
    end

    local mapped = false
    for _, configName in ipairs(wgConfigNames) do
        local fh = io.open(wgDir .. configName .. ".name", "r")
        if fh then
            local ifaceName = fh:read("*a"):gsub("%s+", "")
            fh:close()
            if ifaceName and ifaceName ~= "" then
                wgInterfaceMap[ifaceName] = configName
                mapped = true
            end
        end
    end

    if not mapped and #wgConfigNames > 0 and #wgIfaces > 0 then
        if #wgConfigNames == #wgIfaces then
            table.sort(wgConfigNames)
            table.sort(wgIfaces)
            for i, configName in ipairs(wgConfigNames) do
                wgInterfaceMap[wgIfaces[i]] = configName
            end
            mapped = true
        elseif #wgConfigNames == 1 and #wgIfaces == 1 then
            wgInterfaceMap[wgIfaces[1]] = wgConfigNames[1]
            mapped = true
        end
    end

    if not mapped and #wgIfaces > 0 then
        for _, iface in ipairs(wgIfaces) do
            if not wgInterfaceMap[iface] then
                wgInterfaceMap[iface] = "WireGuard"
            end
        end
    end

    return wgInterfaceMap
end

local function getListeningProcessMap()
    local handle = io.popen("lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null")
    if not handle then return {} end
    local result = handle:read("*a")
    handle:close()

    local map = {}
    for line in result:gmatch("[^\r\n]+") do
        local process = line:match("^(%S+)")
        local port = line:match("%*:(%d+)") or line:match(":(%d+)%s")
        if process and port then
            if not map[port] then
                map[port] = process
            end
        end
    end
    return map
end

local function determineClashAppName(processList, listeningMap, apiPort)
    local listener = listeningMap[apiPort]
    if listener then
        if listener == "FlClash" or listener == "FlClashCore" then return "FlClash" end
        if listener:lower():match("karing") then return "Karing" end
        if listener:lower():match("sing") then return "sing-box" end
        if listener:lower():match("mihomo") then return "FlClash" end
    end

    if processList then
        if processList:match("FlClash") then return "FlClash" end
        if processList:match("[Kk]aring") then return "Karing" end
        if processList:match("sing-box") then return "sing-box" end
    end

    return "Clash"
end

local function getClashAppInfos(processList, listeningMap)
    -- Skip the local API probes entirely unless a Clash-family process is
    -- actually running: otherwise the 4 sequential curls just hit
    -- connection-refused and waste a full status refresh. This is the single
    -- heaviest part of getVPNInfo (it now also runs on a background timer).
    if not processList or not (processList:match("Clash") or processList:match("FlClash")
            or processList:match("FlClashCore") or processList:match("[Kk]aring")
            or processList:match("sing%-box") or processList:match("mihomo")) then
        return {}
    end

    local ports = { "9090", "9097", "7892", "11227" }
    local infos = {}
    local seenPorts = {}

    for _, port in ipairs(ports) do
        if not seenPorts[port] then
            local handle = io.popen("curl -s --connect-timeout 0.3 http://127.0.0.1:" .. port .. "/configs 2>/dev/null")
            if handle then
                local result = handle:read("*a")
                handle:close()

                if result and result:match("tun") then
                    seenPorts[port] = true
                    local tunEnable = result:match('"tun"%s*:%s*{[^}]*"enable"%s*:%s*(true)')
                    local tunDevice = result:match('"device"%s*:%s*"([^"]+)"')
                    local mode = result:match('"mode"%s*:%s*"(%w+)"')
                    local mixedPort = result:match('"mixed-port"%s*:%s*(%d+)')
                    local socksPort = result:match('"socks-port"%s*:%s*(%d+)')
                    local httpPort = result:match('"port"%s*:%s*(%d+)')

                    local appName = determineClashAppName(processList, listeningMap, port)
                    local tunEnabled = tunEnable == "true"

                    local hasConnections = true
                    if not tunEnabled then
                        hasConnections = false
                        local connHandle = io.popen("curl -s --connect-timeout 0.3 http://127.0.0.1:" .. port .. "/connections 2>/dev/null")
                        if connHandle then
                            local connResult = connHandle:read("*a")
                            connHandle:close()
                            if connResult and connResult:match('"chains"') then
                                for chains in connResult:gmatch('"chains"%s*:%s*%[([^%]]*)%]') do
                                    if not chains:match("DIRECT") and not chains:match("COMPATIBLE") and not chains:match("REJECT") then
                                        hasConnections = true
                                        break
                                    end
                                end
                            end
                        end
                    end

                    table.insert(infos, {
                        appName = appName,
                        device = tunDevice,
                        tunEnabled = tunEnabled,
                        mode = mode,
                        mixedPort = mixedPort,
                        socksPort = socksPort,
                        httpPort = httpPort,
                        apiPort = port,
                        hasConnections = hasConnections
                    })
                end
            end
        end
    end

    return infos
end

local function identifyTunnelApp(iface, clashAppInfos)
    for _, info in ipairs(clashAppInfos or {}) do
        if info.tunEnabled and info.device == iface then
            return { name = info.appName, source = info.mode or "TUN" }
        end
    end
    return nil
end

local function getRemainingTunnelInterfaces(ifaceDetails, wgInterfaceMap, processList, clashAppInfos)
    local otherIfaces = {}
    for iface, det in pairs(ifaceDetails) do
        if iface:match("^utun") or iface:match("^tun") or iface:match("^tap") or iface:match("^ipsec") or iface:match("^ppp") then
            if det.hasIPv4 or det.hasIPv6 then
                local displayName = wgInterfaceMap[iface]
                local source = wgInterfaceMap[iface] and "WireGuard" or nil

                if not displayName then
                    local appInfo = identifyTunnelApp(iface, clashAppInfos)
                    if appInfo then
                        displayName = appInfo.name
                        source = appInfo.source
                    end
                end

                if not displayName then
                    displayName = iface
                    source = "Tunnel"
                end

                table.insert(otherIfaces, {
                    name = displayName,
                    type = "Interface",
                    status = "Connected",
                    interface = iface,
                    details = det,
                    source = source
                })
            end
        end
    end
    return otherIfaces
end

local knownProxyApps = {
    { process = "Hiddify", name = "Hiddify" },
    { process = "FlClash", name = "FlClash" },
    { process = "FlClashCore", name = "FlClash" },
    { process = "sing-box", name = "sing-box" },
    { process = "Karing", name = "Karing" },
    { process = "karing", name = "Karing" },
    { process = "mihomo", name = "FlClash" },
}

local function getHiddifyConnectionStatus()
    local logPath = os.getenv("HOME") .. "/Library/Application Support/app.hiddify.com/app.log"
    local handle = io.popen("tail -30 '" .. logPath .. "' 2>/dev/null")
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()

    local lastStatus = nil
    for line in result:gmatch("[^\r\n]+") do
        local status = line:match("connection status: (%w+)")
        if status then
            lastStatus = status
        end
    end
    return lastStatus
end

local function getProxyVPNs(processList, existingVPNs, clashAppInfos, listeningMap)
    local proxyVPNs = {}
    local wifiService = M.getWiFiServiceName()

    local detectedApps = {}
    for _, v in ipairs(existingVPNs) do
        detectedApps[v.name] = true
    end

    if not detectedApps["Hiddify"] and processList and processList:match("Hiddify") then
        local hiddifyStatus = getHiddifyConnectionStatus()
        if hiddifyStatus == "CONNECTED" then
            table.insert(proxyVPNs, {
                name = "Hiddify",
                type = "Proxy",
                status = "Connected",
                interface = nil,
                details = nil,
                source = "Proxy"
            })
            detectedApps["Hiddify"] = true
        end
    end

    for _, info in ipairs(clashAppInfos or {}) do
        if not info.tunEnabled and not detectedApps[info.appName] and info.hasConnections then
            table.insert(proxyVPNs, {
                name = info.appName,
                type = "Proxy",
                status = "Connected",
                interface = nil,
                details = nil,
                source = "Proxy"
            })
            detectedApps[info.appName] = true
        end
    end

    local proxyPort = nil
    local proxyTypes = { "getwebproxy", "getsecurewebproxy", "getsocksfirewallproxy" }
    for _, cmd in ipairs(proxyTypes) do
        local h = io.popen("/usr/sbin/networksetup -" .. cmd .. " " .. shellQuote(wifiService) .. " 2>/dev/null")
        if h then
            local result = h:read("*a")
            h:close()
            if result:match("Enabled: Yes") then
                local port = result:match("Port:%s*(%d+)")
                if port and port ~= "0" then
                    proxyPort = port
                    break
                end
            end
        end
    end

    if not proxyPort then return proxyVPNs end

    local listenerProcess = listeningMap[proxyPort]
    if listenerProcess then
        for _, app in ipairs(knownProxyApps) do
            if listenerProcess == app.process and not detectedApps[app.name] then
                table.insert(proxyVPNs, {
                    name = app.name,
                    type = "Proxy",
                    status = "Connected",
                    interface = nil,
                    details = nil,
                    source = "Proxy"
                })
                detectedApps[app.name] = true
                break
            end
        end
    end

    for _, info in ipairs(clashAppInfos or {}) do
        if not info.tunEnabled and not detectedApps[info.appName] and info.hasConnections then
            local proxyPorts = { info.mixedPort, info.socksPort, info.httpPort }
            for _, p in ipairs(proxyPorts) do
                if p and tostring(p) == proxyPort then
                    table.insert(proxyVPNs, {
                        name = info.appName,
                        type = "Proxy",
                        status = "Connected",
                        interface = nil,
                        details = nil,
                        source = "Proxy"
                    })
                    detectedApps[info.appName] = true
                    break
                end
            end
        end
    end

    return proxyVPNs
end

local function parseDefaultRoutes(family)
    local byInterface = {}
    local handle = io.popen("/usr/sbin/netstat -rn -f " .. family .. " 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()
        for line in result:gmatch("[^\r\n]+") do
            local toks = {}
            for word in line:gmatch("%S+") do table.insert(toks, word) end
            if toks[1] == "default" and toks[2] and #toks >= 3 then
                -- Netif position varies by macOS version (Refs/Use columns may be omitted),
                -- so take the last token that looks like an interface name (en0, utun5, ...).
                local iface = nil
                for i = #toks, 3, -1 do
                    if toks[i]:match("^%a+%d+$") then
                        iface = toks[i]
                        break
                    end
                end
                if iface then
                    byInterface[iface] = byInterface[iface] or {}
                    if not byInterface[iface].gateway then
                        byInterface[iface].gateway = toks[2]
                    end
                end
            end
        end
    end
    return byInterface
end

-- utun tunnels install their default route with a link-layer gateway (link#N),
-- so the usable IPv4 gateway has to come from the interface's point-to-point
-- peer address, reported by ifconfig as "inet <local> --> <peer>".
local function getInterfacePeerGateways()
    local peers = {}
    local handle = io.popen("/sbin/ifconfig 2>/dev/null")
    if not handle then return peers end
    local result = handle:read("*a")
    handle:close()

    local currentInterface = nil
    for line in result:gmatch("[^\r\n]+") do
        local name = line:match("^(%w[%w%d]+):")
        if name then
            currentInterface = name
            peers[name] = peers[name] or {}
        elseif currentInterface and peers[currentInterface] then
            -- NOTE: "-->" must stay unescaped; in Lua patterns "%->" only matches "->"
            -- (the "%>" swallows the ">"), which never matches real ifconfig output.
            local peer = line:match("inet%d*%s+(%d+%.%d+%.%d+%.%d+)%s+-->%s+(%d+%.%d+%.%d+%.%d+)")
            if peer then
                peers[currentInterface].gateway = peer
            end
        end
    end
    return peers
end

local function getDefaultRouteInterface(isIPv6)
    local familyFlag = isIPv6 and " -inet6" or ""
    local handle = io.popen("/sbin/route -n get" .. familyFlag .. " default 2>/dev/null")
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    return result:match("interface:%s*(%S+)")
end

local function getVPNRouteMap()
    return {
        v4 = parseDefaultRoutes("inet"),
        v6 = parseDefaultRoutes("inet6"),
        peers = getInterfacePeerGateways(),
        defaultIface4 = getDefaultRouteInterface(false),
        defaultIface6 = getDefaultRouteInterface(true)
    }
end

function M.getVPNInfo()
    local vpnInfo = {}
    local routeMap = getVPNRouteMap()
    local wifiDevice = M.getWiFiDevice() or "en0"

    local processList = getRunningProcesses()
    local listeningMap = getListeningProcessMap()
    local ifaceDetails = getInterfaceDetails(wifiDevice)
    local scutilVPNs = getSystemVPNs(ifaceDetails, processList)
    local wgInterfaceMap = getWireGuardInterfaceMap()
    local clashAppInfos = getClashAppInfos(processList, listeningMap)
    local otherIfaces = getRemainingTunnelInterfaces(ifaceDetails, wgInterfaceMap, processList, clashAppInfos)

    for _, v in ipairs(scutilVPNs) do table.insert(vpnInfo, v) end
    for _, v in ipairs(otherIfaces) do table.insert(vpnInfo, v) end

    local proxyVPNs = getProxyVPNs(processList, vpnInfo, clashAppInfos, listeningMap)
    for _, v in ipairs(proxyVPNs) do table.insert(vpnInfo, v) end

    for _, v in ipairs(vpnInfo) do
        if v.interface then
            local r4 = routeMap.v4[v.interface]
            local r6 = routeMap.v6[v.interface]
            local gateway4 = r4 and r4.gateway or nil
            -- Prefer a real routable gateway; when the route table only offers
            -- link#N for this interface, fall back to the tunnel peer address.
            if (not gateway4 or gateway4:match("^link#")) and routeMap.peers[v.interface] then
                gateway4 = routeMap.peers[v.interface].gateway
            end
            if gateway4 and gateway4 ~= "" or r6 then
                v.route = { gateway4 = (gateway4 and gateway4 ~= "") and gateway4 or nil, gateway6 = r6 and r6.gateway or nil }
            end
            v.defaultEgress4 = (routeMap.defaultIface4 == v.interface)
            v.defaultEgress6 = (routeMap.defaultIface6 == v.interface)
        else
            v.route = nil
            v.defaultEgress4 = false
            v.defaultEgress6 = false
        end
    end

    return vpnInfo
end

function M.configureIPv6(wifiInterface, v6mode, ipv6, prefix, gateway)
    if v6mode == "manual" and ipv6 and prefix and gateway then
        M.runWithSudo("/usr/sbin/networksetup -setv6manual " .. shellQuote(wifiInterface) .. " " .. shellQuote(ipv6) .. " " .. shellQuote(prefix) .. " " .. shellQuote(gateway))
    elseif v6mode == "automatic" then
        M.runWithSudo("/usr/sbin/networksetup -setv6automatic " .. shellQuote(wifiInterface))
    else
        M.runWithSudo("/usr/sbin/networksetup -setv6off " .. shellQuote(wifiInterface))
    end
end

return M