-- ~/.hammerspoon/wifi_autoconfig/i18n.lua
local M = {}

M.VERSION = "3.0.0"

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
        log_retry_cmd_invalid = "executeWithRetry - cmdFn 无效",
        log_retry_cb_invalid = "executeWithRetry - callback 无效",
        log_retry_cb_lost = "executeWithRetry - 回调函数已失效",
        log_retry_exhausted = "executeWithRetry - 重试次数用尽，失败",
        log_retry_attempt = "executeWithRetry - 第 %d 次重试，等待 %s 秒",

        -- Audit / switching
        log_manual_detect = "手动强制重新检测网络",
        log_ssid_change = "检测到无线网络环境变更: [%s] -> [%s]",
        log_ssid_changed = "showNetworkReport - SSID已变更: %s -> %s",
        log_wifi_sleep = "网卡休眠或未连接任何无线网络",
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

        recent_system_logs = "最近系统日志",

        config_source_custom = "自定义策略",
        config_source_global = "全局兜底策略",
        config_source_dhcp = "DHCP自动获取",
        config_source_editor = "编辑器临时配置",

        popup_title_config_success = "无线网络配置应用成功",
        popup_title_dhcp_success = "网络已设置为 DHCP",
        popup_title_force_apply_success = "强制覆写网络配置成功",
        popup_title_confirm_force_apply = "确认强制应用网络配置",

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
        menu_status_connected = "已连接",
        menu_status_disabled = "已禁用",

        menu_label_ssid = "SSID",
        menu_label_ipv4 = "IPv4",
        menu_label_ip = "IP",
        menu_label_netmask = "子网掩码",
        menu_label_gateway = "网关",
        menu_label_ipv6 = "IPv6",
        menu_label_prefix = "前缀",
        menu_label_dns = "DNS",

        label_ssid = "📶 SSID",
        label_signal = "📡 信号强度",
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
        ui_invalid_ip = "IP地址格式错误",
        ui_invalid_netmask = "子网掩码格式错误",
        ui_invalid_gateway = "网关地址格式错误",
        ui_invalid_dns = "DNS服务器地址格式错误",
        ui_save_success = "配置已保存",
        ui_delete_success = "网络配置已删除",

        system_auto = "系统自动获取",
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
        log_retry_cmd_invalid = "executeWithRetry - cmdFn is invalid",
        log_retry_cb_invalid = "executeWithRetry - callback is invalid",
        log_retry_cb_lost = "executeWithRetry - callback is no longer valid",
        log_retry_exhausted = "executeWithRetry - retries exhausted, giving up",
        log_retry_attempt = "executeWithRetry - retry #%d, waiting %s seconds",

        -- Audit / switching
        log_manual_detect = "Manual force network detection",
        log_ssid_change = "Detected wireless network change: [%s] -> [%s]",
        log_ssid_changed = "showNetworkReport - SSID changed: %s -> %s",
        log_wifi_sleep = "WiFi interface is sleeping or not connected",
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

        recent_system_logs = "Recent System Logs",

        config_source_custom = "Custom Policy",
        config_source_global = "Global Fallback",
        config_source_dhcp = "DHCP Auto",
        config_source_editor = "Editor Temp Config",

        popup_title_config_success = "Network Configuration Applied",
        popup_title_dhcp_success = "Network Set to DHCP",
        popup_title_force_apply_success = "Force Apply Network Configuration",
        popup_title_confirm_force_apply = "Confirm Force Apply",

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
        menu_status_connected = "Connected",
        menu_status_disabled = "Disabled",

        menu_label_ssid = "SSID",
        menu_label_ipv4 = "IPv4",
        menu_label_ip = "IP",
        menu_label_netmask = "Subnet Mask",
        menu_label_gateway = "Gateway",
        menu_label_ipv6 = "IPv6",
        menu_label_prefix = "Prefix",
        menu_label_dns = "DNS",

        label_ssid = "📶 SSID",
        label_signal = "📡 Signal",
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
        ui_invalid_ip = "Invalid IP address format",
        ui_invalid_netmask = "Invalid subnet mask format",
        ui_invalid_gateway = "Invalid gateway address format",
        ui_invalid_dns = "Invalid DNS server address format",
        ui_save_success = "Configuration saved",
        ui_delete_success = "Network configuration deleted",

        system_auto = "Auto",
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
