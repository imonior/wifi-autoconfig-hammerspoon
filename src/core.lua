-- ~/.hammerspoon/wifi_autoconfig/core.lua
local wifi = require("hs.wifi")
local utils = require("wifi_autoconfig.utils")
local i18n = require("wifi_autoconfig.i18n")

local M = {}

-- The Wi-Fi service name and the hardware port device are stable most of the
-- time, so they are cached to keep them off the hot path. But they are NOT
-- permanent: macOS renames a service when you rename it in Network Settings
-- ("Wi-Fi" -> "Wi-Fi (2)" happens routinely), and plugging in an external Wi-Fi
-- dongle moves the interface from en0 to something else. Serving a stale value
-- here means writing an IP/DNS configuration to the WRONG service, so both
-- entries expire and can be dropped on demand.
local NETINFO_CACHE_TTL = 300

local cachedWiFiServiceName = nil
local cachedWiFiServiceTime = 0
local cachedWiFiDevice = nil
local cachedWiFiDeviceTime = 0

-- Drop both caches. init.lua calls this whenever the network state changes so a
-- renamed service or a new interface is picked up immediately instead of after
-- the TTL.
function M.invalidateInterfaceCache()
    cachedWiFiServiceName = nil
    cachedWiFiServiceTime = 0
    cachedWiFiDevice = nil
    cachedWiFiDeviceTime = 0
end

-- networksetup normally returns instantly, but a wedged helper would leave
-- io.popen blocked on read("*a") forever. A hard timeout is not available
-- here: hs.task on this machine exposes only the streaming API
-- (waitUntilExit() takes no timeout and returns the task object), so wrapping
-- it would mean turning this into an async call and reworking every caller.
-- All callers already sit inside waitForCondition timer callbacks, so a stall
-- delays the apply sequence rather than freezing Hammerspoon. What we CAN
-- bound is the log: a runaway command must not flood the log file.
local LOG_OUTPUT_LIMIT = 2000

local function truncateForLog(s)
    s = tostring(s or "")
    if #s <= LOG_OUTPUT_LIMIT then return s end
    return s:sub(1, LOG_OUTPUT_LIMIT) .. "... (" .. #s .. " bytes total)"
end

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

    local result = truncateForLog(handle:read("*a"))
    local success, _, exitCode = handle:close()

    utils.log(i18n.t("log_cmd_output", result))

    local ok = (exitCode == 0)
    if not ok then
        utils.log(i18n.t("log_cmd_failed", fullCmd))
        utils.log(i18n.t("log_cmd_error", result))
    end
    return ok, result
end

-- Resolve the Wi-Fi service name. Two passes on purpose:
--   1. exact match, so a second service that merely contains "Wi-Fi"
--      (e.g. "Wi-Fi Backup") can never be picked up by accident;
--   2. substring fallback, so a service the user renamed in Network Settings
--      (macOS appends " (2)" to duplicates) is still found rather than
--      silently falling back to the hardcoded "Wi-Fi" that no longer exists.
local function matchWiFiServiceLine(line)
    if line:match("^%s*Wi%-Fi%s*$") or line:match("^%s*无线网络%s*$") then
        return line:match("^%s*(.-)%s*$")
    end
    return nil
end

function M.getWiFiServiceName()
    if cachedWiFiServiceName and (os.time() - cachedWiFiServiceTime) < NETINFO_CACHE_TTL then
        return cachedWiFiServiceName
    end
    local handle = io.popen('/usr/sbin/networksetup -listallnetworkservices')
    if not handle then return "Wi-Fi" end
    local result = handle:read("*a")
    handle:close()

    local loose = nil
    for line in result:gmatch("[^\r\n]+") do
        if line:match("^%s*%*") then
            -- Disabled services are prefixed with an asterisk; skip them.
        else
            local exact = matchWiFiServiceLine(line)
            if exact then
                cachedWiFiServiceName = exact
                cachedWiFiServiceTime = os.time()
                return cachedWiFiServiceName
            end
            if not loose and (line:match("Wi%-Fi") or line:match("无线网络")) then
                loose = line:match("^%s*(.-)%s*$")
            end
        end
    end

    cachedWiFiServiceName = loose or "Wi-Fi"
    cachedWiFiServiceTime = os.time()
    return cachedWiFiServiceName
end

function M.getWiFiDevice()
    if cachedWiFiDevice and (os.time() - cachedWiFiDeviceTime) < NETINFO_CACHE_TTL then
        return cachedWiFiDevice
    end
    local handle = io.popen("/usr/sbin/networksetup -listallhardwareports")
    if not handle then return "en0" end
    local result = handle:read("*a")
    handle:close()
    for port, dev in result:gmatch("Hardware Port:%s*([^\n]+)%s*\nDevice:%s*([^\n]+)") do
        if port and port:match("Wi%-Fi") then
            cachedWiFiDevice = dev:match("^%s*(.-)%s*$")
            cachedWiFiDeviceTime = os.time()
            return cachedWiFiDevice
        end
    end
    cachedWiFiDevice = "en0"
    cachedWiFiDeviceTime = os.time()
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
        local cmd = "/usr/sbin/networksetup -getairportnetwork " .. shellQuote(wifiDevice)
        
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

    return status
end

-- `networksetup -getinfo` prints IPv4 and IPv6 in the SAME output, so one call can
-- report both families. M.getServiceInfo() returns that raw output (or nil) and the
-- parsers below are pure - they never shell out. Anything that needs both families
-- (the status report, the menu poller, the editor sync) must call
-- M.getCurrentIPInfo() rather than the single-family helpers, or it pays for the
-- same process twice.
function M.getServiceInfo(wifiInterface)
    local handle = io.popen("/usr/sbin/networksetup -getinfo " .. shellQuote(wifiInterface))
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    return result
end

-- Returns: ip, gateway, netmask, mode
function M.parseIPv4Info(result)
    if not result then return "", "", "", "" end
    local v4mode = i18n.t("v4_dhcp")
    if result:match("Manual Configuration") then v4mode = i18n.t("v4_manual") end

    return result:match("IP address:%s*([%d%.]+)") or "",
           result:match("Router:%s*([%d%.]+)") or "",
           result:match("Subnet mask:%s*([%d%.]+)") or "",
           v4mode
end

function M.getCurrentIPv4Info(wifiInterface)
    return M.parseIPv4Info(M.getServiceInfo(wifiInterface))
end

-- Parses the active IPv6 status and the global unicast address actually assigned.
-- `result` is the raw output of M.getServiceInfo(); it is parsed in place, with
-- an ifconfig fallback applied only when IPv6 is on but no address was reported.
-- Returns: mode, ip, prefix, router
function M.parseIPv6Info(result)
    if not result then return i18n.t("v6_off"), i18n.t("unassigned"), "", "" end

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
        local ih = io.popen("ifconfig " .. shellQuote(dev))
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

function M.getCurrentIPInfo(wifiInterface)
    local info = M.getServiceInfo(wifiInterface)
    local ip, gw, nm, v4mode = M.parseIPv4Info(info)
    local v6mode, v6ip, v6prefix, v6router = M.parseIPv6Info(info)
    return ip, gw, nm, v4mode, v6mode, v6ip, v6prefix, v6router
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
    return #dnsList > 0 and table.concat(dnsList, ", ") or i18n.t("dns_empty")
end

-- The address a peer sees for this machine, read twice because an enabled system proxy
-- replaces the answer: the same request then leaves through that proxy's exit, so the
-- direct address and the address your traffic actually appears from are two different
-- facts worth having side by side. Only an HTTP or HTTPS proxy set on the service can be
-- read here; a PAC-only setup reports no proxy and the direct address is the whole story.
--
-- Every one of these requests leaves the machine, so the budget stays small: the first
-- endpoint that answers wins and the rest are never tried, and a dead or hijacked path
-- costs about a second per endpoint rather than hanging the Lua thread.
--
-- The list is ordered by how likely it is to answer where this module runs. Measured on
-- the development machine: the three well-known echo services were all unreachable while
-- the machine had working Internet - their names resolve into the 198.18.0.0/15 range a
-- TUN-mode proxy hands out for fake-IP, and with no proxy listening the requests just run
-- down their timeout - while ip.3322.net answered in 0.7s with a bare address. A chain
-- made only of foreign services therefore reads "failed" on a machine that is plainly
-- online, which is the one case this row exists to make visible.
local EGRESS_ENDPOINTS = {
    "https://api.ipify.org",
    "https://ip.3322.net/",
    "https://ifconfig.co/ip",
    "https://ip.sb/ip",
}

local function isIPv4(value)
    local octets = {}
    for octet in value:gmatch("%d+") do octets[#octets + 1] = tonumber(octet) end
    if #octets ~= 4 then return false end
    for _, octet in ipairs(octets) do
        if octet > 255 then return false end
    end
    return true
end

local function asAddress(text)
    local value = text and text:match("^%s*(.-)%s*$")
    if not value or value == "" or #value > 45 then return nil end
    if value:match("^%d+%.%d+%.%d+%.%d+$") and isIPv4(value) then return value end
    -- An IPv6 literal needs at least two colons. Anything else a service might hand back -
    -- an error page, a hostname, a JSON body - has no place in this row.
    if value:match("^[%x:]+$") and select(2, value:gsub(":", "")) >= 2 then return value end
    return nil
end

local function probeEgress(proxyURL)
    for _, endpoint in ipairs(EGRESS_ENDPOINTS) do
        -- --noproxy is what makes the direct reading mean "this interface's own address":
        -- curl would otherwise pick up proxy variables from the environment.
        local via = proxyURL and ("--proxy " .. shellQuote(proxyURL)) or "--noproxy '*'"
        local handle = io.popen("/usr/bin/curl -s --connect-timeout 0.5 --max-time 1 " ..
            via .. " " .. shellQuote(endpoint) .. " 2>/dev/null")
        if handle then
            local result = handle:read("*a")
            handle:close()
            local address = asAddress(result)
            if address then return address end
        end
    end
    return nil
end

M.getEgressIP = probeEgress

local function proxyField(result, name)
    for line in result:gmatch("[^\r\n]+") do
        -- Anchored at the line start on purpose: the same output carries
        -- "Authenticated Proxy Enabled: 0", which is not whether the proxy is in use.
        local value = line:match("^%s*" .. name .. ":%s*(.-)%s*$")
        if value then return value end
    end
    return nil
end

local function usablePort(text)
    return text ~= nil and tonumber(text) ~= nil and tonumber(text) > 0
end

function M.getSystemProxyURL(wifiInterface)
    for _, query in ipairs({ "-getwebproxy", "-getsecurewebproxy" }) do
        local handle = io.popen("/usr/sbin/networksetup " .. query .. " " ..
            shellQuote(wifiInterface) .. " 2>/dev/null")
        if handle then
            local result = handle:read("*a")
            handle:close()
            -- networksetup reports "Port: 0" for a service with no proxy set, which is the
            -- same answer as an enabled entry that was never completed; neither is somewhere
            -- a request can be sent.
            local server, port = proxyField(result, "Server"), proxyField(result, "Port")
            if proxyField(result, "Enabled") == "Yes" and server and server ~= ""
                and usablePort(port) then
                return "http://" .. server .. ":" .. port
            end
        end
    end
    return nil
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

-- The same processes, but with their arguments. A launcher that starts a Clash-family
-- core normally names the API endpoint in the arguments rather than in a port anyone can
-- scan for, so this is where that endpoint is found. Kept apart from the list above on
-- purpose: matching a bare name against arguments would let any command line that merely
-- mentions an app (a terminal title, a grep) claim that app is running.
local function getProcessArguments()
    local handle = io.popen("/bin/ps -axo command= 2>/dev/null")
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
    -- +c 0 stops lsof from cutting the command column to nine characters. The names this
    -- map is searched with are longer than that ("FlClashCore", "verge-mihomo"), so with
    -- the default width the comparison could never be satisfied and the port would look
    -- unowned by any known app.
    local handle = io.popen("lsof -iTCP -sTCP:LISTEN -P -n +c 0 2>/dev/null")
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

-- In a Lua pattern '-' is not a literal character, it is the lazy quantifier applied
-- to the item BEFORE it. "sing-box" thus means "sin", then as few "g" as possible,
-- then "box" - the hyphen is never matched, and the whole thing fails against the
-- text "sing-box" (verified: it returns nil, while "sing%-box" matches). Process
-- names are escaped before being used as patterns for exactly this reason, so an app
-- whose name contains '-' cannot silently stop being detected.
local function hasProcess(processList, name)
    if not processList or not name then return false end
    return processList:match((name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))) ~= nil
end

-- Which app a Clash-family core belongs to is written in its own binary name, so one
-- marker table answers all three lookups: the process line that carries a controller
-- socket, the process that owns a listening port, and (below) the running-process list.
-- The order is the content: the generic "mihomo" core is what FlClash runs, so the two
-- apps that embed mihomo under their own names have to be recognised before it is.
local CLASH_NAME_MARKERS = {
    { marker = "flclash", name = "FlClash" },
    { marker = "karing", name = "Karing" },
    { marker = "sing-box", name = "sing-box" },
    { marker = "verge-mihomo", name = "Clash Verge" },
    { marker = "clash-verge", name = "Clash Verge" },
    { marker = "mihomo-party", name = "mihomo-party" },
    { marker = "mihomo", name = "FlClash" },
}

local function namedByMarker(text)
    if not text then return nil end
    local lowered = text:lower()
    for _, entry in ipairs(CLASH_NAME_MARKERS) do
        if lowered:find(entry.marker, 1, true) then
            return entry.name
        end
    end
    return nil
end

local function determineClashAppName(processList, listeningMap, apiPort, ownerHint)
    local name = namedByMarker(ownerHint) or namedByMarker(apiPort and listeningMap[apiPort])
    if name then return name end

    if processList then
        if hasProcess(processList, "FlClash") then return "FlClash" end
        if hasProcess(processList, "Karing") or hasProcess(processList, "karing") then return "Karing" end
        if hasProcess(processList, "sing-box") then return "sing-box" end
        if hasProcess(processList, "Clash Verge") or hasProcess(processList, "clash-verge")
            or hasProcess(processList, "verge-mihomo") then return "Clash Verge" end
    end

    return "Clash"
end

local function findFlagValue(line, flag)
    -- The same flag arrives as `-flag value`, `-flag=value` or `--flag=value`, and its
    -- value may be quoted because macOS paths carry spaces. The hyphens of the flag are
    -- escaped for the same reason as the JSON keys below.
    local pattern = "%-%-?" .. flag:gsub("%-", "%%-")
    return line:match(pattern .. "=%s*\"([^\"]+)\"")
        or line:match(pattern .. "%s+\"([^\"]+)\"")
        or line:match(pattern .. "=%s*(%S+)")
        or line:match(pattern .. "%s+(%S+)")
end

-- Where a Clash-family core serves its API is no longer always a TCP port: Clash Verge's
-- service starts its core with `-ext-ctl-unix <path>` and `external-controller: ''`, so
-- nothing listens on 9090 or 9097 at all, and a scan of fixed port numbers finds an empty
-- machine - which is how a running tunnel ends up shown under its interface name instead of
-- the program that made it. Read the endpoint from the arguments the core was started with;
-- the fixed port list stays as the fallback for cores launched with only a TCP controller.
local function getClashControllerEndpoints(argsText)
    local endpoints, seen = {}, {}
    for line in (argsText or ""):gmatch("[^\r\n]+") do
        local lowered = line:lower()
        if lowered:match("mihomo") or lowered:match("clash") then
            for _, candidate in ipairs({
                { flag = "ext-ctl-unix", kind = "unix" },
                { flag = "ext-ctl", kind = "tcp" },
            }) do
                local value = findFlagValue(line, candidate.flag)
                if value then
                    local key = candidate.kind .. ":" .. value
                    if not seen[key] then
                        seen[key] = true
                        if candidate.kind == "unix" then
                            endpoints[#endpoints + 1] = { socket = value, owner = line }
                        else
                            endpoints[#endpoints + 1] = { addr = value, owner = line }
                        end
                    end
                end
            end
        end
    end
    return endpoints
end

local CONTROLLER_PORTS = { "9090", "9097", "7892", "11227" }

-- One request to one endpoint. Every endpoint is on this machine, so the whole call is
-- capped at about a second: this runs inside the status refresh, and a core that accepts a
-- connection but never answers must not hold the menu open.
local function fetchFromController(endpoint, path)
    local target
    if endpoint.socket then
        -- The URL is only the request line curl writes; over a socket transport its host
        -- is never resolved, but curl refuses the request without one.
        target = "--unix-socket " .. shellQuote(endpoint.socket) .. " " ..
            shellQuote("http://localhost" .. path)
    else
        target = shellQuote("http://" .. endpoint.addr .. path)
    end
    local handle = io.popen("/usr/bin/curl -s --connect-timeout 0.3 --max-time 1 " ..
        target .. " 2>/dev/null")
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    return result
end

local function getClashAppInfos(processList, listeningMap, argsText)
    -- Skip the local API probes entirely unless a Clash-family process is
    -- actually running: otherwise the sequential curls just hit
    -- connection-refused and waste a full status refresh. This is the single
    -- heaviest part of getVPNInfo (it now also runs on a background timer).
    if not processList or not (hasProcess(processList, "Clash") or hasProcess(processList, "FlClash")
            or hasProcess(processList, "FlClashCore") or hasProcess(processList, "Karing")
            or hasProcess(processList, "karing") or hasProcess(processList, "sing-box")
            or hasProcess(processList, "mihomo")) then
        return {}
    end

    local endpoints = getClashControllerEndpoints(argsText)
    for _, port in ipairs(CONTROLLER_PORTS) do
        endpoints[#endpoints + 1] = { addr = "127.0.0.1:" .. port, port = port }
    end

    local infos = {}

    for _, endpoint in ipairs(endpoints) do
        local result = fetchFromController(endpoint, "/configs")
        if result and result:match("tun") then
            local tunEnable = result:match('"tun"%s*:%s*{[^}]*"enable"%s*:%s*(true)')
            local tunDevice = result:match('"device"%s*:%s*"([^"]+)"')
            local mode = result:match('"mode"%s*:%s*"(%w+)"')
            -- The hyphens are escaped: bare, a hyphen is the lazy quantifier on the
            -- character before it, so '"mixed-port"' asks for "mixed", any number of
            -- "d", then "port" and never matches the JSON key it names.
            local mixedPort = result:match('"mixed%-port"%s*:%s*(%d+)')
            local socksPort = result:match('"socks%-port"%s*:%s*(%d+)')
            local httpPort = result:match('"port"%s*:%s*(%d+)')

            local appName = determineClashAppName(processList, listeningMap, endpoint.port, endpoint.owner)
            local tunEnabled = tunEnable == "true"

            local hasConnections = true
            if not tunEnabled then
                hasConnections = false
                local connResult = fetchFromController(endpoint, "/connections")
                if connResult and connResult:match('"chains"') then
                    for chains in connResult:gmatch('"chains"%s*:%s*%[([^%]]*)%]') do
                        if not chains:match("DIRECT") and not chains:match("COMPATIBLE") and not chains:match("REJECT") then
                            hasConnections = true
                            break
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
                apiPort = endpoint.port,
                hasConnections = hasConnections
            })
        end
    end

    return infos
end

-- The bracket in the row is the evidence kind, like every other VPN row, so the core's
-- running mode does not travel in it; that is a separate fact and gets its own row.
local function identifyTunnelApp(iface, clashAppInfos)
    for _, info in ipairs(clashAppInfos or {}) do
        if info.tunEnabled and info.device == iface then
            return { name = info.appName, source = "TUN", mode = info.mode }
        end
    end
    return nil
end

-- The tunnels are collected by walking the interface map, and a hash walk has no order:
-- two interfaces belonging to one client could come out on either side of another client's
-- row, and the same system state could list them differently after two reloads. Grouped by
-- the kind of evidence that made the row, then by the name it shows, then by the interface
-- number, the block reads the same every time and one client's tunnels stay together.
local TUNNEL_SOURCE_ORDER = { TUN = 1, WireGuard = 2, Tunnel = 3, Proxy = 4 }

local function tunnelSourceRank(source)
    return TUNNEL_SOURCE_ORDER[source] or 5
end

local function tunnelInterfaceNumber(iface)
    return tonumber(iface and iface:match("(%d+)$")) or math.maxinteger
end

-- An unclaimed tunnel is labelled with the interface itself, so its label carries the
-- interface number as text and ordering by that label would rank utun1025 in front of utun7.
-- Such a row joins no name group, so it is ordered by number instead.
local function tunnelNameKey(row)
    if row.name == row.interface then return "" end
    return row.name
end

local function compareTunnelRows(a, b)
    local ra, rb = tunnelSourceRank(a.source), tunnelSourceRank(b.source)
    if ra ~= rb then return ra < rb end
    local ka, kb = tunnelNameKey(a), tunnelNameKey(b)
    if ka ~= kb then return ka < kb end
    local na, nb = tunnelInterfaceNumber(a.interface), tunnelInterfaceNumber(b.interface)
    if na ~= nb then return na < nb end
    return tostring(a.interface) < tostring(b.interface)
end

local function getRemainingTunnelInterfaces(ifaceDetails, wgInterfaceMap, processList, clashAppInfos)
    local otherIfaces = {}
    for iface, det in pairs(ifaceDetails) do
        if iface:match("^utun") or iface:match("^tun") or iface:match("^tap") or iface:match("^ipsec") or iface:match("^ppp") then
            if det.hasIPv4 or det.hasIPv6 then
                local displayName = wgInterfaceMap[iface]
                local source = wgInterfaceMap[iface] and "WireGuard" or nil
                local mode = nil

                if not displayName then
                    local appInfo = identifyTunnelApp(iface, clashAppInfos)
                    if appInfo then
                        displayName = appInfo.name
                        source = appInfo.source
                        mode = appInfo.mode
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
                    source = source,
                    mode = mode
                })
            end
        end
    end

    table.sort(otherIfaces, compareTunnelRows)

    return otherIfaces
end

local knownProxyApps = {
    { process = "Hiddify", name = "Hiddify" },
    { process = "FlClash", name = "FlClash" },
    { process = "FlClashCore", name = "FlClash" },
    { process = "sing-box", name = "sing-box" },
    { process = "Karing", name = "Karing" },
    { process = "karing", name = "Karing" },
    { process = "clash-verge", name = "Clash Verge" },
    { process = "verge-mihomo", name = "Clash Verge" },
    { process = "mihomo", name = "FlClash" },
}

local function getHiddifyConnectionStatus()
    local logPath = os.getenv("HOME") .. "/Library/Application Support/app.hiddify.com/app.log"
    local handle = io.popen("tail -30 " .. shellQuote(logPath) .. " 2>/dev/null")
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

    if not detectedApps["Hiddify"] and hasProcess(processList, "Hiddify") then
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

    -- System-proxy lookup: read the enabled proxy port, then map it back to a
    -- process via listeningMap. That mapping can only ever name one of
    -- knownProxyApps, so if none of them is running there is nothing to find -
    -- skip the three networksetup calls entirely instead of asking the system
    -- about proxies on a machine that runs none.
    local proxyPort = nil
    local anyKnownProxyRunning = false
    for _, app in ipairs(knownProxyApps) do
        if hasProcess(processList, app.process) then
            anyKnownProxyRunning = true
            break
        end
    end

    if anyKnownProxyRunning then
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

-- Which routing-table rows are worth showing as "networks reachable through this
-- tunnel". Skipped: loopback, multicast and broadcast, IPv6 link-local, and a route
-- whose destination equals its gateway (that is the interface's own address, not a
-- network it leads to).
local function isNoiseRoute(dest, gateway)
    local base = dest:match("^(.-)/%d+$") or dest
    if base:match("^fe80") or base:match("^ff") then return true end
    if base:match("^224%.") or base:match("^239%.") then return true end
    if base == "255.255.255.255" then return true end
    if base == "127" or base:match("^127%.") or base == "::1" then return true end
    if gateway and dest == gateway then return true end
    return false
end

-- `netstat -rn` abbreviates IPv4 networks ("10/8", "192.168.1/32"); expand them to
-- full CIDR so the row is unambiguous. IPv6 is already printed in full form.
local function expandNetwork(base, bits)
    local octets = {}
    for o in base:gmatch("%d+") do table.insert(octets, o) end
    if #octets == 0 or #octets >= 4 then return nil end
    while #octets < 4 do table.insert(octets, "0") end
    return table.concat(octets, ".") .. "/" .. bits
end

local function normalizeRouteDest(dest)
    local base, bits = dest:match("^(.-)/(%d+)$")
    if base then
        if base:match(":") then return dest end
        return expandNetwork(base, bits) or dest
    end
    -- A destination with no separator at all is a classful network whose prefix length
    -- netstat left out, because the octets it printed already say it: "1" is 1.0.0.0/8,
    -- "128.0" is 128.0.0.0/16, "192.168" is 192.168.0.0/24. Anything else that arrives
    -- without a slash - a full host address, an IPv6 form, a column that is not a
    -- destination - is passed through rather than guessed at.
    local octetCount = 0
    for _ in dest:gmatch("%d+") do octetCount = octetCount + 1 end
    if octetCount < 1 or octetCount > 3 then return dest end
    if not dest:match("^[%d%.]+$") then return dest end
    return expandNetwork(dest, 8 * octetCount) or dest
end

-- Parses `netstat -rn -f <family>` once and returns two views of the same output:
--   byGateway     - iface -> { gateway = <default-route gateway> }, default routes only
--   byDestination - iface -> { destinations = { "<net>", ... }, count = N }, every
--                   non-default network this interface carries (the routes a VPN
--                   installs), minus the noise filtered above
local function parseRoutes(family)
    local byGateway = {}
    local byDestination = {}
    local handle = io.popen("/usr/sbin/netstat -rn -f " .. family .. " 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()
        for line in result:gmatch("[^\r\n]+") do
            local toks = {}
            for word in line:gmatch("%S+") do table.insert(toks, word) end
            local dest = toks[1]
            if dest and dest ~= "Destination" and #toks >= 3 then
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
                    if dest == "default" then
                        byGateway[iface] = byGateway[iface] or {}
                        if not byGateway[iface].gateway then
                            byGateway[iface].gateway = toks[2]
                        end
                    elseif not isNoiseRoute(dest, toks[2]) then
                        byDestination[iface] = byDestination[iface] or { destinations = {}, count = 0 }
                        byDestination[iface].count = byDestination[iface].count + 1
                        -- Keep a handful of representative destinations; a full-tunnel VPN
                        -- can install thousands, and the menu only wants a summary.
                        if #byDestination[iface].destinations < 6 then
                            table.insert(byDestination[iface].destinations, normalizeRouteDest(dest))
                        end
                    end
                end
            end
        end
    end
    return byGateway, byDestination
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
    local v4gw, v4dest = parseRoutes("inet")
    local v6gw, v6dest = parseRoutes("inet6")
    return {
        v4 = v4gw,
        v6 = v6gw,
        routes4 = v4dest,
        routes6 = v6dest,
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
    local clashAppInfos = getClashAppInfos(processList, listeningMap, getProcessArguments())
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

            -- Split-tunnel summary, kept per family: netstat is read once per
            -- family and the two address spaces mean different things, so the
            -- menu shows one row each rather than a merged total. netstat
            -- abbreviates IPv4 networks; those are expanded by normalizeRouteDest
            -- before they get here.
            local nr4 = routeMap.routes4[v.interface]
            local nr6 = routeMap.routes6[v.interface]
            v.routeNetworks = {
                v4 = (nr4 and nr4.count > 0) and nr4 or nil,
                v6 = (nr6 and nr6.count > 0) and nr6 or nil,
            }
        else
            v.route = nil
            v.routeNetworks = nil
            v.defaultEgress4 = false
            v.defaultEgress6 = false
        end
    end

    return vpnInfo
end

-- Returns one of four statuses, so the apply flow can report what actually happened
-- to IPv6 rather than showing a blanket success popup:
--   "applied"   - the command ran,
--   "failed"    - the command was refused or errored (output carries the reason),
--   "skipped"   - this policy says nothing about IPv6, so the interface keeps its
--                 current setting, which is a normal outcome and not a problem,
--   "incomplete"- a manual IPv6 policy without all three arguments,
--   "unknown"   - a v6mode value that means nothing (a typo, or a field from a future
--                 version) - also not applied, but the user has to hear about it,
--                 because the policy they wrote is not what is running.
--
-- Previously anything that was not manual-with-full-arguments landed in the final
-- else and ran -setv6off. A policy saved before the v6mode field existed, or
-- hand-edited without it, therefore turned IPv6 off on every single network switch -
-- and did so silently, while the "no matching policy" branch of applyNetworkStrategy
-- does not touch IPv6 at all. Only an explicit "off" may disable it now.
function M.configureIPv6(wifiInterface, v6mode, ipv6, prefix, gateway)
    if v6mode == "automatic" then
        local ok, output = M.runWithSudo("/usr/sbin/networksetup -setv6automatic " .. shellQuote(wifiInterface))
        return ok and "applied" or "failed", output
    end

    if v6mode == "off" then
        local ok, output = M.runWithSudo("/usr/sbin/networksetup -setv6off " .. shellQuote(wifiInterface))
        return ok and "applied" or "failed", output
    end

    if v6mode == "manual" then
        if not ipv6 or ipv6 == "" or not prefix or prefix == "" or not gateway or gateway == "" then
            -- The editor only sends all three fields together, so this is a
            -- hand-edited or truncated policy. Applying it half-way would leave a
            -- broken IPv6 address on the interface, which is worse than not trying.
            utils.log(i18n.t("log_v6_manual_incomplete", tostring(wifiInterface)))
            return "incomplete"
        end
        local ok, output = M.runWithSudo("/usr/sbin/networksetup -setv6manual " .. shellQuote(wifiInterface) .. " " .. shellQuote(ipv6) .. " " .. shellQuote(prefix) .. " " .. shellQuote(gateway))
        return ok and "applied" or "failed", output
    end

    -- No v6mode field at all: leave the interface alone.
    if v6mode == nil or v6mode == "" then
        return "skipped"
    end

    utils.log(i18n.t("log_v6_mode_unknown", tostring(v6mode), tostring(wifiInterface)))
    return "unknown"
end

return M