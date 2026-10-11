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
    -- One -getinfo covers both address families; parseIPv4Info and parseIPv6Info
    -- would otherwise each spawn the same process for this report.
    local ip, gw, nm, v4mode, v6mode, v6ip, v6prefix, v6gw = core.getCurrentIPInfo(wifiInterface)
    local activeDns = core.getActiveDNS()

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

-- sudo has no TTY inside io.popen, so a missing NOPASSWD rule cannot be solved by
-- typing a password - the command simply fails. That reads to a user like a broken
-- network rather than a missing permission, so the popup names the cause.
local function sudoNeedsPassword(output)
    local s = tostring(output or ""):lower()
    return s:match("a password is required") ~= nil
        or s:match("no tty") ~= nil
        or s:match("incorrect password attempts") ~= nil
end

local function shortOutput(output)
    local s = tostring(output or "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if #s > 180 then s = s:sub(1, 180) .. "..." end
    return s
end

-- The banner and the report window are two different things, and only one of them is the
-- user's answer. hs.notify raises a Lua error when the system will not take notifications
-- for this app - permission switched off, or the registration lost over a reboot - and that
-- error used to be thrown in the middle of the reporting code, cancelling the report that
-- came after it. A banner that cannot be delivered is now a logged fact, never a reason for
-- the apply to go quiet.
local function notifyBanner(text)
    local ok, err = pcall(function()
        notify.new({ title = i18n.t("notify_title_config_changed"), informativeText = text }):send()
    end)
    if not ok then
        utils.log(i18n.t("log_notify_failed", tostring(err)))
    end
end

local function addProblem(problems, label, ok, output)
    if ok then return end
    if sudoNeedsPassword(output) then
        table.insert(problems, i18n.t("hint_sudo_password_required"))
        return
    end
    local detail = shortOutput(output)
    table.insert(problems, detail ~= "" and (label .. ": " .. detail) or label)
end

-- configureIPv6 says what it did, and only two of those answers mean "nothing to
-- report": "applied", and "skipped" (a policy that says nothing about IPv6, which is a
-- normal outcome). Checking `status ~= "failed"` instead, as this used to, let an
-- incomplete manual policy and a nonsense v6mode pass as success.
local function failIPv6(problems, status, output, v6mode)
    if status == "applied" or status == "skipped" then return end
    if status == "failed" then
        addProblem(problems, i18n.t("problem_ipv6"), false, output)
    elseif status == "incomplete" then
        table.insert(problems, i18n.t("problem_ipv6_incomplete"))
    else
        table.insert(problems, i18n.t("problem_ipv6_unknown_mode", tostring(v6mode)))
    end
end

-- "Did the interface end up able to resolve names" cannot be answered by checking for
-- an empty string: getActiveDNS() replies with a localized "no DNS configured" label
-- when there are no resolvers, and that label is neither empty nor an address. Only a
-- literal IPv4 address counts, so the label is read as "nothing to resolve with".
-- “接口最终能否解析域名”不能用空串判断：没有解析器时 getActiveDNS() 返回的是本地化的
-- “未配置 DNS”标签，它既非空串也不是地址。只有真正的 IPv4 地址才算数，这样标签会被
-- 正确理解为“没有可用解析器”。
local function hasUsableDns(dns)
    if not dns then return false end
    for entry in string.gmatch(dns, "[^,%s]+") do
        if entry:match("^%d+%.%d+%.%d+%.%d+$") then return true end
    end
    return false
end

-- A fallback is not a failure: the machine does resolve names, just not through the
-- servers the policy named. Notes travel with the report so the user can see which
-- resolvers are actually in effect, without turning a successful apply into a partial one.
-- 用了兜底不算失败：机器确实能解析域名，只是用的不是策略里写的那组。提示随报告一起展示，
-- 让用户看到实际生效的是哪组解析器，同时不会把一次成功的应用变成“部分应用”。
function M.withNotes(notes, report)
    if not notes or #notes == 0 then return report end
    return i18n.t("popup_notes_header") .. "\n• " ..
        table.concat(notes, "\n• ") .. "\n\n" .. report
end

-- A Wi-Fi switch can happen again while an earlier sequence is still waiting (up to 15
-- seconds for DHCP, 10 for a static address to show up, 5 for DNS). Those waits resume
-- whenever they like, and the stale one would then push the PREVIOUS network's DNS and
-- IPv6 settings onto the interface that has already moved on. Each sequence therefore
-- takes a token and checks it before every step that follows a wait: a superseded
-- sequence stops touching the network and stops reporting, leaving the newer one alone.
local runSeq = 0

local function nextRun()
    runSeq = runSeq + 1
    return runSeq
end

local function stale(run)
    if run == runSeq then return false end
    utils.log(i18n.t("log_apply_superseded"))
    return true
end

-- problems is a list of step descriptions that did not land. It travels with the
-- report so the popup says "partly applied" instead of claiming success after the
-- networksetup calls were refused.
function M.showNetworkReport(ssid, problems, notes)
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
    ui.showPopup("success", M.resultTitle(problems, i18n.t("popup_title_config_success")),
        M.withProblems(problems, M.withNotes(notes, report)))
    ui.syncHardwareStatusToUI()
end

function M.resultTitle(problems, successTitle)
    if problems and #problems > 0 then
        return i18n.t("popup_title_partial")
    end
    return successTitle
end

function M.withProblems(problems, report)
    if not problems or #problems == 0 then return report end
    return i18n.t("popup_problems_header") .. "\n• " ..
        table.concat(problems, "\n• ") .. "\n\n" .. report
end

-- callback receives `problems`: the list of steps that did not land, empty when the
-- whole sequence applied. Every command here is a sudo networksetup call through
-- io.popen, which has no TTY, so a rejected or failing call used to be invisible -
-- the module reported "configuration applied" after changing nothing.
function M.applyConfigToInterface(wifiInterface, setting, callback, run)
    -- Callers that start a sequence of their own (a stored policy being applied) pass
    -- their token; a caller that does not is superseding whatever is in flight.
    run = run or nextRun()
    local problems = {}
    -- Notes are not problems: they say what was done rather than what failed, and they
    -- must not turn a successful apply into a partial one.
    -- 提示不是问题：它说的是做了什么，而不是什么失败了，不应把成功的应用变成“部分应用”。
    local notes = {}
    local function fail(label, ok, output)
        addProblem(problems, label, ok, output)
    end

    if setting.mode == "manual" then
        local netmask = setting.netmask or "255.255.255.0"

        -- Read the resolvers the interface is using BEFORE it is switched to a static
        -- address: at this point it still holds whatever the network handed it (a DHCP
        -- lease on a fresh connection, or the previous static policy on a re-apply), so
        -- this is the one list known to work on this network. A policy that names no DNS
        -- falls back to it instead of having its resolver list cleared outright.
        -- 在切到静态地址之前读取接口正在使用的解析器：此刻接口还持有网络下发的内容（新连接
        -- 的 DHCP 租约，或重复应用时的上一条静态策略），这是本机唯一已知可用的那组。策略
        -- 未指定 DNS 时就回落到它，而不是把解析器列表清空。
        local dnsBeforeSwitch
        if not (setting.dns and setting.dns:match("%S")) then
            dnsBeforeSwitch = core.getActiveDNS()
        end

        local v6status, v6output = core.configureIPv6(wifiInterface, setting.v6mode, setting.ipv6, setting.v6prefix, setting.v6gateway)
        failIPv6(problems, v6status, v6output, setting.v6mode)

        local v4ok, v4output = core.runWithSudo("/usr/sbin/networksetup -setmanual " .. core.shellQuote(wifiInterface) .. " " .. core.shellQuote(setting.ip) .. " " .. core.shellQuote(netmask) .. " " .. core.shellQuote(setting.gateway))
        fail(i18n.t("problem_ipv4_static"), v4ok, v4output)

        -- A policy that names no DNS cannot be answered with "empty" on a static address:
        -- there is no DHCP lease to supply resolvers, so clearing the list would leave the
        -- machine unable to resolve names while every command reported success. The order
        -- is what this network was already using, then the configured fallback.
        -- 静态地址下，策略未指定 DNS 不能用“清空”来回应：没有 DHCP 租约提供解析器，清空会
        -- 让机器无法解析域名，而命令却全部报成功。顺序是：本网络已在用的 → 用户配置的兜底。
        local dnsFallbackNote
        local targetDns = setting.dns
        if not (targetDns and targetDns:match("%S")) then
            if hasUsableDns(dnsBeforeSwitch) then
                targetDns = dnsBeforeSwitch
                dnsFallbackNote = i18n.t("note_dns_fallback_network", targetDns)
            else
                targetDns = config.getFallbackDns()
                dnsFallbackNote = i18n.t("note_dns_fallback_configured", targetDns)
            end
        end

        local function applyDns()
            if stale(run) then return end

            local dnsOk, dnsOutput = core.setDNSServers(wifiInterface, targetDns)
            fail(i18n.t("problem_dns"), dnsOk, dnsOutput)

            if dnsFallbackNote then
                utils.log(i18n.t("log_dns_fallback", tostring(targetDns)))
            end

            -- Whichever path was taken - the policy's own servers or a fallback - the
            -- interface has to end up able to resolve names. This check used to run only
            -- when the policy named servers, so a cleared list was never verified and a
            -- static interface left with no resolver was reported as a successful apply.
            -- 无论走哪条路径（策略自己的服务器还是兜底），接口最终都必须能解析域名。这个检查
            -- 过去只在策略指定了 DNS 时才跑，所以被清空的列表从不校验，没有解析器的静态接口
            -- 会被报成“应用成功”。
            utils.waitForCondition(function()
                local activeDns = core.getActiveDNS()
                if not hasUsableDns(activeDns) then return false end
                if targetDns and targetDns:match("%S") then
                    local activeSet = {}
                    for entry in string.gmatch(activeDns, "[^,%s]+") do activeSet[entry] = true end
                    for dnsEntry in string.gmatch(targetDns, "[^,%s]+") do
                        if not activeSet[dnsEntry] then return false end
                    end
                end
                return true
            end, 5, 0.5, function(dnsSet)
                if stale(run) then return end
                if not dnsSet then
                    -- Two different failures land here and they are not the same thing to
                    -- the user: no resolvers at all, or resolvers that are not the ones
                    -- that were asked for.
                    -- 这里有两种不同的失败，对用户不是一回事：完全没有解析器，或生效的不是要求的那组。
                    if not hasUsableDns(core.getActiveDNS()) then
                        utils.log(i18n.t("log_warn_dns_unusable"))
                        table.insert(problems, i18n.t("problem_dns_unusable"))
                    else
                        utils.log(i18n.t("log_warn_dns_not_effective"))
                        table.insert(problems, i18n.t("problem_dns_not_effective"))
                    end
                end
                if dnsFallbackNote then table.insert(notes, dnsFallbackNote) end
                if callback then callback(problems, notes) end
            end)
        end

        -- The write itself was refused, so waiting up to 5 seconds for an address
        -- that cannot appear only delays the report.
        if not v4ok then
            applyDns()
            return
        end

        utils.waitForCondition(function()
            local currentIp = core.getCurrentIPv4Info(wifiInterface)
            return currentIp == setting.ip
        end, 10, 0.5, function(ipSet)
            if stale(run) then return end
            if not ipSet then
                utils.log(i18n.t("log_warn_ip_not_effective"))
                table.insert(problems, i18n.t("problem_ipv4_not_effective"))
            end
            applyDns()
        end)
    else
        local ok, output = core.runWithSudo("/usr/sbin/networksetup -setdhcp " .. core.shellQuote(wifiInterface))
        fail(i18n.t("problem_ipv4_dhcp"), ok, output)

        local function finish()
            if stale(run) then return end

            local v6status, v6output = core.configureIPv6(wifiInterface, setting.v6mode, setting.ipv6, setting.v6prefix, setting.v6gateway)
            failIPv6(problems, v6status, v6output, setting.v6mode)

            -- On DHCP an empty policy really does mean "let the lease supply the resolvers",
            -- so clearing the list is the right answer here. What was missing is the check
            -- that the resolvers actually arrived: this branch used to verify nothing at
            -- all, while the static branch at least verified the servers the policy named.
            -- DHCP 下策略留空确实是“让租约提供解析器”，所以清空列表在这里是正确的。缺的是
            -- 解析器是否真的到位的检查：这个分支过去什么都不校验，而静态分支至少会校验策略
            -- 指定的那组。
            local targetDns = setting.dns or ""
            local dnsOk, dnsOutput = core.setDNSServers(wifiInterface, targetDns)
            fail(i18n.t("problem_dns"), dnsOk, dnsOutput)

            utils.waitForCondition(function()
                local activeDns = core.getActiveDNS()
                if not hasUsableDns(activeDns) then return false end
                if targetDns:match("%S") then
                    local activeSet = {}
                    for entry in string.gmatch(activeDns, "[^,%s]+") do activeSet[entry] = true end
                    for dnsEntry in string.gmatch(targetDns, "[^,%s]+") do
                        if not activeSet[dnsEntry] then return false end
                    end
                end
                return true
            end, 5, 0.5, function(dnsSet)
                if stale(run) then return end
                if not dnsSet then
                    if not hasUsableDns(core.getActiveDNS()) then
                        utils.log(i18n.t("log_warn_dns_unusable"))
                        table.insert(problems, i18n.t("problem_dns_unusable"))
                    else
                        utils.log(i18n.t("log_warn_dns_not_effective"))
                        table.insert(problems, i18n.t("problem_dns_not_effective"))
                    end
                end
                if callback then callback(problems, notes) end
            end)
        end

        if not ok then
            finish()
            return
        end

        utils.waitForCondition(function()
            local ip, _, _, v4mode = core.getCurrentIPv4Info(wifiInterface)
            -- A stale address from a previous static policy can linger after the DHCP
            -- command has been issued, so the check also verifies that the interface
            -- reports its configuration mode as DHCP (or the localized equivalent).
            return ip ~= "" and ip ~= "0.0.0.0" and v4mode == i18n.t("v4_dhcp")
        end, 15, 0.5, function(ipObtained)
            if stale(run) then return end
            if not ipObtained then
                utils.log(i18n.t("log_warn_no_dhcp"))
                table.insert(problems, i18n.t("problem_no_dhcp_address"))
            end
            finish()
        end)
    end
end

-- `onSettled(applied)` reports how the sequence ended so the caller can decide whether
-- the policy is confirmed on the interface. It fires exactly once per call, and never
-- from a stale run: that sequence was superseded, and the one that replaced it reports.
function M.applyNetworkStrategy(ssid, onSettled)
    local function settle(applied)
        if onSettled then onSettled(applied) end
    end

    if config.degraded then
        -- With no readable policies, config.current[ssid] is nil for every SSID, and
        -- the branch below would "fall back" by forcing the live interface onto DHCP.
        -- A typo in config.json must not take a static network offline.
        utils.log(i18n.t("log_apply_skipped_degraded"))
        settle(false)
        return
    end

    local wifiInterface = core.getWiFiServiceName()
    local run = nextRun()
    local setting = config.current[ssid]

    if not setting then
        setting = config.current["__DEFAULT__"]
    end

    if setting then
        -- A policy can also come from a hand-edit or from a version of the module
        -- that saved fewer fields, and every command below runs through the
        -- passwordless sudoers rule, so the values are checked before any of them
        -- is issued. An unusable policy is skipped: the interface keeps what the
        -- system already gave it instead of being forced onto DHCP.
        local valid, errMsg = config.validateConfig(setting)
        if not valid then
            utils.log(i18n.t("log_policy_invalid", ssid, tostring(errMsg)))
            settle(false)
            notifyBanner("SSID: " .. ssid .. "\n" .. i18n.t("notify_policy_invalid"))
            return
        end

        utils.log(i18n.t("log_apply_rule", ssid, setting.mode))

        M.applyConfigToInterface(wifiInterface, setting, function(problems, notes)
            local modeText = setting.mode == "manual" and i18n.t("notify_static_ip") or i18n.t("notify_dhcp")
            if problems and #problems > 0 then
                modeText = modeText .. "\n" .. i18n.t("notify_partial", #problems)
            end
            -- The report goes on the timer first: everything after this line is a courtesy
            -- notice, and a courtesy notice that fails must not cancel the report.
            utils.wait(1, function()
                M.showNetworkReport(ssid, problems, notes)
            end)
            settle(not problems or #problems == 0)
            notifyBanner("SSID: " .. ssid .. "\n" .. modeText)
        end, run)
    else
        utils.log(i18n.t("log_no_config_fallback"))
        local ok, output = core.runWithSudo("/usr/sbin/networksetup -setdhcp " .. core.shellQuote(wifiInterface))

        local problems = {}
        addProblem(problems, i18n.t("problem_ipv4_dhcp"), ok, output)

        utils.waitForCondition(function()
            local ip, _, _, v4mode = core.getCurrentIPv4Info(wifiInterface)
            -- Same dual check: the interface must report DHCP mode and hold a usable address.
            return ip ~= "" and ip ~= "0.0.0.0" and v4mode == i18n.t("v4_dhcp")
        end, 15, 0.5, function(ipObtained)
            if stale(run) then return end

            if not ipObtained then
                utils.log(i18n.t("log_warn_no_dhcp"))
                table.insert(problems, i18n.t("problem_no_dhcp_address"))
            end

            addProblem(problems, i18n.t("problem_dns"), core.setDNSServers(wifiInterface, ""))

            local dhcpText = i18n.t("notify_dhcp")
            if #problems > 0 then
                dhcpText = dhcpText .. "\n" .. i18n.t("notify_partial", #problems)
            end
            utils.wait(1, function()
                M.showNetworkReport(ssid, problems)
            end)
            settle(#problems == 0)
            notifyBanner("SSID: " .. ssid .. "\n" .. dhcpText)
        end)
    end
end

function M.setCurrentNetworkToDHCP()
    local wifiInterface = core.getWiFiServiceName()
    utils.log(i18n.t("log_manual_dhcp"))

    local run = nextRun()
    local problems = {}
    local ok, output = core.runWithSudo("/usr/sbin/networksetup -setdhcp " .. core.shellQuote(wifiInterface))
    addProblem(problems, i18n.t("problem_ipv4_dhcp"), ok, output)

    failIPv6(problems, core.configureIPv6(wifiInterface, "automatic", "", "", ""), nil, "automatic")

    utils.waitForCondition(function()
        local ip, _, _, v4mode = core.getCurrentIPv4Info(wifiInterface)
        return ip ~= "" and ip ~= "0.0.0.0" and v4mode == i18n.t("v4_dhcp")
    end, 15, 0.5, function(ipObtained)
        if stale(run) then return end

        if not ipObtained then
            utils.log(i18n.t("log_warn_no_dhcp"))
            table.insert(problems, i18n.t("problem_no_dhcp_address"))
        end

        addProblem(problems, i18n.t("problem_dns"), core.setDNSServers(wifiInterface, ""))

        utils.wait(1, function()
            local report = M.buildNetworkReport(i18n.t("config_source_dhcp"))
            ui.showPopup("success", M.resultTitle(problems, i18n.t("popup_title_dhcp_success")),
                M.withProblems(problems, report))
            ui.syncHardwareStatusToUI()
        end)
    end)
end

return M