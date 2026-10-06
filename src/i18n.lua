-- ~/.hammerspoon/wifi_autoconfig/i18n.lua
local M = {}

local locales = {
    zh = {
        app_name = "Wi-Fi 自动配置",
        unknown = "未知",
        not_connected = "未连接",
        unassigned = "未分配",
        auto = "自动获取",

        -- Editor / WebView lifecycle
        log_window_closed = "windowCallback - 窗口关闭，editorView 设置为 nil",
        log_window_created = "showEditor - 窗口创建成功，editorView: %s",
        log_delay_sync = "延迟同步网络状态 - SSID: %s",
        log_refresh_editor = "refreshEditor - editorView: %s",
        log_refresh_editor_type = "refreshEditor - editorView type: %s",
        log_refresh_nil = "refreshEditor - editorView 为 nil，无法刷新",
        log_refresh_content = "refreshEditor - 刷新编辑器内容",
        log_config_count = "refreshEditor - 配置数量: %d",
        log_js_success = "refreshEditor - JS执行成功",
        log_js_fail = "refreshEditor - JS执行失败: %s",
        log_sync_status = "syncHardwareStatusToUI - SSID: %s, DNS: %s",
        log_sync_js_fail = "syncHardwareStatusToUI - JS执行失败: %s",
        log_show_popup = "showPopup - 已显示新弹窗: %s",
        log_close_old_popup = "showPopup - 已关闭旧的成功弹窗",
        log_close_log_popup = "showPopup - 已关闭旧的日志弹窗",
        log_cleared = "日志已清空",
        log_close_editor = "编辑器关闭",

        -- Core / driver layer
        log_cmd_exec = "驱动层执行: %s",
        log_cmd_open_fail = "命令执行失败: 无法打开进程",
        log_cmd_output = "命令输出: %s",
        log_cmd_failed = "命令执行失败: %s",
        log_cmd_error = "错误信息: %s",

        -- Async helpers
        log_wait_no_callback = "WARNING: wait() 未提供回调 - 已忽略",
        log_waitfor_check_invalid = "waitForCondition - checkFn 无效",
        log_waitfor_cb_invalid = "waitForCondition - callback 无效",
        log_waitfor_cb_lost = "waitForCondition - 回调函数已失效",
        log_waitfor_timeout = "waitForCondition - 超时，已等待 %s 秒",

        -- Audit / switching
        log_manual_detect = "手动强制重新检测网络",
        log_ssid_change = "检测到无线网络环境变更: [%s] -> [%s]",
        log_ssid_changed = "showNetworkReport - SSID已变更: %s -> %s",
        log_wifi_sleep = "网卡休眠或未连接任何无线网络",
        log_wifi_flap_recovered = "复查发现链路仍在同一无线网络上，先前的断开读数属于误判 - SSID: %s（不下发命令、不显示弹窗）",
        log_wifi_down_confirmed = "复查确认无线网络已断开，清除已应用记录 - SSID: %s（下次连上按新网络重新应用规则）",
        log_apply_rule = "应用规则 -> SSID: %s, 模式: %s",
        log_no_config_fallback = "未分配任何配置，降级为系统默认 DHCP",
        log_manual_dhcp = "手动将当前网络设置为 DHCP",
        log_init_success = "Wi-Fi 自动配置模块初始化成功。",
        log_force_apply_with_data = "强制应用编辑器数据: %s",
        log_force_apply_no_data = "强制应用未提供配置数据",
        log_warn_ip_not_effective = "警告: IPv4地址设置可能未生效",
        log_warn_dns_not_effective = "警告: DNS设置可能未生效",
        log_warn_no_dhcp = "警告: 未获取到DHCP地址",
        log_validation_failed = "配置校验失败 - SSID: %s, 原因: %s",
        log_saved_config = "已保存配置 - SSID: %s",
        log_deleted_config = "已删除配置 - SSID: %s",
        log_config_parse_failed = "config.json 无法解析为配置对象，已保留原文件并暂停写入: %s",
        log_config_entry_ignored = "config.json 中键为 %s 的条目不是配置对象，已忽略",
        log_config_write_blocked = "配置无法解析，已拒绝写入，以免用不完整的内容覆盖 config.json: %s",
        log_config_write_failed = "config.json 写入失败（编码或打开文件出错）",
        log_apply_skipped_degraded = "config.json 无法解析，已跳过自动应用，以免把静态网络误降级为 DHCP",
        log_apply_superseded = "已切换到更新的网络，上一次尚未完成的配置流程不再写入 DNS/IPv6，也不会重复上报",
        log_apply_retry_scheduled = "SSID %s 的配置流程未完全生效，第 %d 次重试将在 %d 秒后开始",
        log_apply_gave_up = "SSID %s 的配置流程重试 %d 次后仍未完全生效，已停止自动重试；网络保持当前状态，可点「强制重新检测」",
        log_policy_invalid = "SSID %s 的策略未通过校验，已跳过应用，不会下发给 networksetup: %s",
        notify_policy_invalid = "该网络策略中存在非法字段，已跳过应用，网络设置保持原样",
        log_v6_manual_incomplete = "IPv6 手动配置参数不完整（接口 %s 缺少地址/前缀/网关），已跳过 IPv6 设置",
        log_v6_mode_unknown = "未知的 IPv6 配置类型「%s」（接口 %s），已跳过，不会改动现有 IPv6 设置",
        log_config_deferred = "config.json 仍未修正，模块保持暂停写入与跳过自动切换: %s",
        log_config_recovered = "config.json 重新解析成功，已恢复写入与自动切换: %s",
        log_config_missing = "config.json 已消失或变成空文件，但内存中仍有 %d 条策略；已暂停写入并跳过自动切换，等待恢复文件: %s",
        log_modal_blocked = "已有一个模态框在等待用户处理，跳过这次的弹窗: %s",
        log_modal_error = "模态框显示失败: %s",
        ui_config_unreadable = "配置文件无法解析。你的策略仍完整保留在该文件里，模块已暂停写入并跳过自动切换。修正语法后点「重新读取」:",
        ui_config_unreadable_title = "config.json 无法解析",
        ui_config_still_unreadable = "文件仍然无法解析。请继续修正语法，再点「重新读取」:",
        ui_config_missing_title = "config.json 不见了",
        ui_config_missing = "config.json 已消失或变成空文件，但模块内存里还留着 %d 条网络策略。如果就此接受空配置，这些策略会被全部清空，下次切换网络时静态网络还会被降级成 DHCP。模块已暂停写入并跳过自动切换。请把该文件找回来（或从备份恢复），然后点「重新读取」；点「稍后处理」会保持网络现状不变:",
        ui_config_still_missing = "文件仍然不存在或仍然为空。请恢复该文件后再点「重新读取」:",
        ui_save_failed_degraded = "策略未保存：config.json 当前无法解析，磁盘上的内容没有被改动",
        popup_retry_read = "重新读取",
        popup_handle_later = "稍后处理",
        popup_ok = "知道了",

        recent_system_logs = "最近系统日志",

        config_source_custom = "自定义策略",
        config_source_global = "全局兜底策略",
        config_source_dhcp = "DHCP自动获取",
        config_source_editor = "编辑器临时配置",

        popup_title_config_success = "无线网络配置应用成功",
        popup_title_dhcp_success = "网络已设置为 DHCP",
        popup_title_force_apply_success = "强制覆写网络配置成功",
        popup_title_confirm_force_apply = "确认强制应用网络配置",
        popup_title_partial = "网络配置仅部分生效",
        popup_problems_header = "以下步骤未能完成：",
        hint_sudo_password_required = "缺少免密 sudo 规则，网络配置命令无法执行（模块无法弹出密码框，因此不会提示输入）。请运行 install.sh 添加规则",
        problem_ipv6 = "IPv6 设置写入失败",
        problem_ipv6_incomplete = "IPv6 手动配置缺少地址/前缀/网关，已跳过 IPv6，接口保持原状",
        problem_ipv6_unknown_mode = "IPv6 配置类型「%s」无法识别，已跳过，不会改动现有 IPv6 设置",
        problem_ipv4_static = "静态 IPv4 写入失败",
        problem_ipv4_dhcp = "切换 DHCP 失败",
        problem_dns = "DNS 写入失败",
        problem_ipv4_not_effective = "静态 IPv4 地址在等待时间内未生效",
        problem_dns_not_effective = "DNS 在等待时间内未生效",
        problem_no_dhcp_address = "未获取到 DHCP 地址",
        notify_partial = "%d 个步骤未完成，详见弹窗",

        popup_confirm_force_apply_detail = "确定要强制应用以下网络配置到当前网卡吗？",
        popup_confirm = "确认",
        popup_cancel = "取消",

        notify_title_config_changed = "网络配置已自动变更",
        notify_static_ip = "模式: 静态IP",
        notify_dhcp = "模式: DHCP动态获取",

        menu_open_settings = "打开设置中心",
        menu_view_logs = "查看运行日志",
        menu_update_dhcp = "更新当前网络为「DHCP」",
        menu_force_detect = "强制重新检测网络",

        menu_status_wifi_header = "📶 当前 WiFi 状态",
        menu_status_vpn_header = "🔐 VPN / 虚拟网卡",
        menu_status_vpn_interface = "接口",
        menu_status_disconnected = "未连接",
        menu_vpn_default_egress = "默认出口",
        menu_status_connected = "已连接",
        menu_status_disabled = "已禁用",

        menu_label_ssid = "SSID",
        menu_label_ipv4 = "IPv4",
        menu_label_ipv4_with_gw = "IPv4/gateway",
        menu_label_ip = "IP",
        menu_label_netmask = "子网掩码",
        menu_label_gateway = "网关",
        menu_label_ipv6 = "IPv6",
        menu_label_prefix = "前缀",
        menu_label_dns = "DNS",
        menu_label_route = "路由",
        menu_vpn_routes_more = "共 %d 条",

        label_ssid = "📶 SSID",
        label_config_source = "🔧 配置来源",
        label_ipv4 = "━━━━━━━━ IPv4 ━━━━━━━━",
        label_ipv6 = "━━━━━━━━ IPv6 ━━━━━━━━",
        label_dns = "━━━━━━━━ DNS ━━━━━━━━",
        label_system = "━━━━━━━━ 系统信息 ━━━━━━━━",
        label_address = "地址",
        label_netmask = "子网掩码",
        label_gateway = "网关",
        label_mode = "模式",
        label_interface = "接口名称",
        label_device = "设备名称",

        ui_mode_static = "静态IP",
        ui_mode_dhcp = "DHCP自动获取",
        ui_validation_error = "配置校验失败",
        ui_invalid_mode = "网络配置模式只能是 dhcp 或 manual",
        ui_invalid_ip = "IP地址格式错误",
        ui_invalid_netmask = "子网掩码格式错误",
        ui_gateway_required = "静态模式必须填写网关地址",
        ui_invalid_gateway = "网关地址格式错误",
        ui_invalid_dns = "DNS服务器地址格式错误",
        ui_invalid_ipv6 = "IPv6 地址格式错误",
        ui_invalid_v6prefix = "IPv6 前缀长度格式错误",
        ui_invalid_v6gateway = "IPv6 网关地址格式错误",
        ui_invalid_v6mode = "IPv6 配置类型只能是 automatic、off 或 manual（留空表示不改动）",
        ui_save_success = "配置已保存",
        ui_delete_success = "网络配置已删除",

        system_auto = "系统自动获取",
        dns_empty = "未配置 DNS",
        v4_dhcp = "DHCP",
        v4_manual = "静态",
        v6_off = "关闭",
        v6_automatic = "自动",
        v6_manual = "手动",
        v6_enabled = "启用",
        v6_link_local = "仅本地链路"
    },
    en = {
        app_name = "Wi-Fi AutoConfig for Hammerspoon",
        unknown = "Unknown",
        not_connected = "Not Connected",
        unassigned = "Unassigned",
        auto = "Auto",

        -- Editor / WebView lifecycle
        log_window_closed = "windowCallback - Window closed, editorView set to nil",
        log_window_created = "showEditor - Window created successfully, editorView: %s",
        log_delay_sync = "Delay sync network status - SSID: %s",
        log_refresh_editor = "refreshEditor - editorView: %s",
        log_refresh_editor_type = "refreshEditor - editorView type: %s",
        log_refresh_nil = "refreshEditor - editorView is nil, cannot refresh",
        log_refresh_content = "refreshEditor - Refreshing editor content",
        log_config_count = "refreshEditor - Config count: %d",
        log_js_success = "refreshEditor - JS execution successful",
        log_js_fail = "refreshEditor - JS execution failed: %s",
        log_sync_status = "syncHardwareStatusToUI - SSID: %s, DNS: %s",
        log_sync_js_fail = "syncHardwareStatusToUI - JS execution failed: %s",
        log_show_popup = "showPopup - Displayed new popup: %s",
        log_close_old_popup = "showPopup - Closed old success popup",
        log_close_log_popup = "showPopup - Closed old log popup",
        log_cleared = "Logs cleared",
        log_close_editor = "Editor closed",

        -- Core / driver layer
        log_cmd_exec = "Driver executing: %s",
        log_cmd_open_fail = "Command failed: cannot open process",
        log_cmd_output = "Command output: %s",
        log_cmd_failed = "Command failed: %s",
        log_cmd_error = "Error output: %s",

        -- Async helpers
        log_wait_no_callback = "WARNING: wait() called without callback - ignoring",
        log_waitfor_check_invalid = "waitForCondition - checkFn is invalid",
        log_waitfor_cb_invalid = "waitForCondition - callback is invalid",
        log_waitfor_cb_lost = "waitForCondition - callback is no longer valid",
        log_waitfor_timeout = "waitForCondition - timed out after %s seconds",

        -- Audit / switching
        log_manual_detect = "Manual force network detection",
        log_ssid_change = "Detected wireless network change: [%s] -> [%s]",
        log_ssid_changed = "showNetworkReport - SSID changed: %s -> %s",
        log_wifi_sleep = "WiFi interface is sleeping or not connected",
        log_wifi_flap_recovered = "Re-check found the link still associated, so the earlier down reading was a false one - SSID: %s (no commands, no report popup)",
        log_wifi_down_confirmed = "Re-check confirms the network really is gone, forgetting what was applied - SSID: %s (the next association is re-audited as a new network)",
        log_apply_rule = "Applying rule -> SSID: %s, Mode: %s",
        log_no_config_fallback = "No configuration assigned, falling back to default DHCP",
        log_manual_dhcp = "Manually setting current network to DHCP",
        log_init_success = "Wi-Fi AutoConfig module initialized successfully.",
        log_force_apply_with_data = "Force apply with editor data: %s",
        log_force_apply_no_data = "Force apply without configuration data",
        log_warn_ip_not_effective = "Warning: IPv4 address may not be effective",
        log_warn_dns_not_effective = "Warning: DNS may not be effective",
        log_warn_no_dhcp = "Warning: Failed to obtain DHCP address",
        log_validation_failed = "Config validation failed - SSID: %s, reason: %s",
        log_saved_config = "Saved configuration - SSID: %s",
        log_deleted_config = "Deleted configuration - SSID: %s",
        log_config_parse_failed = "config.json did not parse into a configuration object; file kept as-is, writing paused: %s",
        log_config_entry_ignored = "config.json entry %s is not a configuration object, ignored",
        log_config_write_blocked = "Configuration unreadable; write refused so an incomplete table cannot replace config.json: %s",
        log_config_write_failed = "Failed to write config.json (could not encode or open the file)",
        log_apply_skipped_degraded = "config.json unreadable; skipped auto-apply rather than downgrading a static network to DHCP",
        log_apply_superseded = "A newer network switch started; the previous apply sequence stopped writing DNS/IPv6 and reporting",
        log_apply_retry_scheduled = "Apply for %s did not fully take effect; retry %d starts in %d seconds",
        log_apply_gave_up = "Apply for %s still failed after %d retries; automatic retry stopped. The network keeps its current settings - use Force Detect to try again",
        log_policy_invalid = "Policy for %s failed validation; skipped instead of sending it to networksetup: %s",
        notify_policy_invalid = "This policy contains an invalid field, so it was skipped and the network settings were left as they were",
        log_v6_manual_incomplete = "IPv6 manual policy on %s is missing an address, prefix or gateway; IPv6 left unchanged",
        log_v6_mode_unknown = "Unknown IPv6 mode %s on %s; IPv6 left unchanged (only an explicit \"off\" disables it)",
        log_config_deferred = "config.json still does not parse; writing stays refused and auto-apply stays skipped: %s",
        log_config_recovered = "config.json parsed successfully again; writing and auto-apply resumed: %s",
        log_config_missing = "config.json is gone or empty while %d policies are still loaded; writing refused and auto-apply skipped until the file comes back: %s",
        log_modal_blocked = "A dialog is already waiting for an answer; this one was not raised: %s",
        log_modal_error = "Failed to show the dialog: %s",
        ui_config_unreadable = "config.json could not be parsed. Your policies are still intact in that file, and the module has stopped writing to it and skipped automatic switching. Fix the syntax, then press Retry:",
        ui_config_unreadable_title = "config.json cannot be parsed",
        ui_config_still_unreadable = "The file still does not parse. Keep fixing the syntax, then press Retry:",
        ui_config_missing_title = "config.json has gone missing",
        ui_config_missing = "config.json is gone or has become an empty file, while %d network policies are still loaded here. Accepting that would discard every one of them, and the next network switch would then find no policy and force a static network onto DHCP. Writing is paused and automatic switching is skipped. Restore the file (for example from a backup), then press Retry; Handle it later leaves the current network settings untouched:",
        ui_config_still_missing = "The file is still missing or still empty. Bring it back, then press Retry:",
        ui_save_failed_degraded = "Not saved: config.json currently cannot be parsed, so nothing was written to it",
        popup_retry_read = "Retry",
        popup_handle_later = "Handle it later",
        popup_ok = "OK",

        recent_system_logs = "Recent System Logs",

        config_source_custom = "Custom Policy",
        config_source_global = "Global Fallback",
        config_source_dhcp = "DHCP Auto",
        config_source_editor = "Editor Temp Config",

        popup_title_config_success = "Network Configuration Applied",
        popup_title_dhcp_success = "Network Set to DHCP",
        popup_title_force_apply_success = "Force Apply Network Configuration",
        popup_title_confirm_force_apply = "Confirm Force Apply",
        popup_title_partial = "Network Configuration Only Partially Applied",
        popup_problems_header = "These steps did not complete:",
        hint_sudo_password_required = "No passwordless sudo rule, so the networksetup commands could not run (the module cannot ask for a password). Run install.sh to add the rule",
        problem_ipv6 = "Failed to write the IPv6 settings",
        problem_ipv6_incomplete = "The manual IPv6 policy is missing an address, prefix or gateway, so IPv6 was left as it was",
        problem_ipv6_unknown_mode = "Unknown IPv6 mode %s; the existing IPv6 settings were left unchanged",
        problem_ipv4_static = "Failed to write the static IPv4 settings",
        problem_ipv4_dhcp = "Failed to switch to DHCP",
        problem_dns = "Failed to write the DNS servers",
        problem_ipv4_not_effective = "The static IPv4 address did not appear while waiting",
        problem_dns_not_effective = "The DNS servers did not appear while waiting",
        problem_no_dhcp_address = "No DHCP address was obtained",
        notify_partial = "%d steps did not complete, see the popup",

        popup_confirm_force_apply_detail = "Are you sure you want to force apply the following network configuration?",
        popup_confirm = "Confirm",
        popup_cancel = "Cancel",

        notify_title_config_changed = "Network Configuration Changed",
        notify_static_ip = "Mode: Static IP",
        notify_dhcp = "Mode: DHCP",

        menu_open_settings = "Open Settings",
        menu_view_logs = "View Logs",
        menu_update_dhcp = "Set Current Network to DHCP",
        menu_force_detect = "Force Network Detection",

        menu_status_wifi_header = "📶 Current WiFi Status",
        menu_status_vpn_header = "🔐 VPN / Virtual NIC",
        menu_status_vpn_interface = "Interface",
        menu_status_disconnected = "Not Connected",
        menu_vpn_default_egress = "Default egress",
        menu_status_connected = "Connected",
        menu_status_disabled = "Disabled",

        menu_label_ssid = "SSID",
        menu_label_ipv4 = "IPv4",
        menu_label_ipv4_with_gw = "IPv4/gateway",
        menu_label_ip = "IP",
        menu_label_netmask = "Subnet Mask",
        menu_label_gateway = "Gateway",
        menu_label_ipv6 = "IPv6",
        menu_label_prefix = "Prefix",
        menu_label_dns = "DNS",
        menu_label_route = "Route",
        menu_vpn_routes_more = "%d total",

        label_ssid = "📶 SSID",
        label_config_source = "🔧 Source",
        label_ipv4 = "━━━━━━━━ IPv4 ━━━━━━━━",
        label_ipv6 = "━━━━━━━━ IPv6 ━━━━━━━━",
        label_dns = "━━━━━━━━ DNS ━━━━━━━━",
        label_system = "━━━━━━━━ System ━━━━━━━━",
        label_address = "Address",
        label_netmask = "Subnet Mask",
        label_gateway = "Gateway",
        label_mode = "Mode",
        label_interface = "Interface",
        label_device = "Device",

        ui_mode_static = "Static IP",
        ui_mode_dhcp = "DHCP",
        ui_validation_error = "Validation Error",
        ui_invalid_mode = "Mode must be either dhcp or manual",
        ui_invalid_ip = "Invalid IP address format",
        ui_invalid_netmask = "Invalid subnet mask format",
        ui_gateway_required = "A gateway address is required in static mode",
        ui_invalid_gateway = "Invalid gateway address format",
        ui_invalid_dns = "Invalid DNS server address format",
        ui_invalid_ipv6 = "Invalid IPv6 address format",
        ui_invalid_v6prefix = "Invalid IPv6 prefix length",
        ui_invalid_v6gateway = "Invalid IPv6 gateway address",
        ui_invalid_v6mode = "IPv6 mode must be automatic, off or manual (empty leaves IPv6 unchanged)",
        ui_save_success = "Configuration saved",
        ui_delete_success = "Network configuration deleted",

        system_auto = "Auto",
        dns_empty = "No DNS configured",
        v4_dhcp = "DHCP",
        v4_manual = "Static",
        v6_off = "Off",
        v6_automatic = "Automatic",
        v6_manual = "Manual",
        v6_enabled = "Enabled",
        v6_link_local = "Link-local only"
    }
}

M.currentLocale = "zh"

function M.detectLocale()
    local host = require("hs.host")
    local currentLocale = host.locale.current()

    if currentLocale and currentLocale:sub(1, 2) == "zh" then
        M.currentLocale = "zh"
    else
        M.currentLocale = "en"
    end
    return M.currentLocale
end

M.detectLocale()

function M.t(key, ...)
    local locale = locales[M.currentLocale] or locales.zh
    local value = locale[key]
    if value == nil then
        value = locales.en[key] or key
    end
    if select('#', ...) > 0 then
        return string.format(value, ...)
    end
    return value
end

function M.getLocale()
    return M.currentLocale
end

function M.setLocale(locale)
    if locales[locale] then
        M.currentLocale = locale
        return true
    end
    return false
end

return M
