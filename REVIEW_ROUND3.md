## Wi-Fi AutoConfig for Hammerspoon 第三轮完整审查报告（2026-07-25）

### 本轮变更概述

相比上一轮分析，项目完成了大量重构和优化。以下先梳理已修复项，再列出仍存在的问题。

---

### 已修复的上轮问题（确认通过）

**1. WiFi 服务名/设备名缓存** ✅
`core.lua:8-9` 新增 `cachedWiFiServiceName` / `cachedWiFiDevice`，`getWiFiServiceName()` 和 `getWiFiDevice()` 首次调用后缓存，后续直接返回。消除了最高频的重复 fork。

**2. 架构拆分 — init.lua 瘦身** ✅
- `menu_builder.lua`（150 行）：菜单栏 styled-text 构建 + 暗色模式检测 + 颜色方案
- `network_apply.lua`（171 行）：`applyNetworkStrategy()` + `buildNetworkReport()` + `showNetworkReport()` + `setCurrentNetworkToDHCP()`
- init.lua 从 590 行降至 262 行，职责清晰

**3. `getVPNInfo()` 拆分为 4 个 helper** ✅
`core.lua:265-431`：`getInterfaceDetails()` → `getSystemVPNs()` → `getWireGuardInterfaceMap()` → `getRemainingTunnelInterfaces()`，`getVPNInfo()` 本体仅 13 行编排。可读性和可测试性大幅提升。

**4. JS 注入转义修复** ✅
`utils.lua:37-42` 新增 `escapeJS()` 函数，正确处理 `\\` → `\\\\`、`'` → `\\'`、`"` → `\\"`、换行/回车/tab 的转义。`web_view.lua:114-115` 和 `151-152` 已改用 `utils.escapeJS()`。修复了含反斜杠 SSID 导致 JS 语法错误的风险。

**5. config.lua 重复 URL handler 合并** ✅
`config.lua:143-150` 提取了 `handleForceApply(params)` 公共函数，`force_apply_network` 和 `force_apply_network_with_confirm` 两个 handler 共用同一逻辑。

**6. config.lua JSON 解码加了 pcall** ✅
`config.lua:92-93` 和 `121-122`：`save_wifi_scene` 和 `delete_wifi_scene` 的 JSON 解码都用 `pcall` 包裹，防止畸形 JSON 导致整个 handler 崩溃。

**7. README 目录结构已更新** ✅
反映了 `src/` + `scripts/` 的新布局，新增了 `menu_builder.lua` 和 `network_apply.lua` 的说明。

**8. `cleanOldLogs()` 逻辑优化** ✅
`utils.lua:49-72`：新增 `lastEntryWithinRange` 标记，只有当日志条目的时间在 7 天内时才保留后续的无时间戳续行，避免了旧的无日期行被永久保留的问题。

**9. i18n 新增键** ✅
添加了 `log_close_editor`、`log_manual_detect`、`log_force_apply_no_data` 等键（部分仍有遗漏，见下文）。

**10. 启动流程简化** ✅
移除了旧的 `runInitialAudit` + 5 次重试机制，改为直接调用 `performNetworkAudit()` + 2 秒后 `syncHardwareStatusToUI()`。更简洁，WiFi 未就绪时由 watcher 后续触发。

---

### 仍存在的问题

#### P0 — 性能

**1. 菜单栏点击仍然全同步阻塞**

`init.lua:80-84` 的菜单回调：

```lua
M.menuBarItem:setMenu(function()
    local success, result = pcall(function()
        updateNetworkStatusCache()  -- 10+ 个 io.popen 阻塞调用
        return menuBuilder.buildNetworkStatusMenuItems(cachedNetworkStatus)
    end)
```

`updateNetworkStatusCache()`（init.lua:33-46）在每次菜单点击时同步执行：`getCurrentWiFiStatus()`（2~4 进程）+ `getCurrentIPv4Info()` + `getCurrentIPv6Info()` + `getActiveDNS()` + `getVPNInfo()`（3~5+ 进程）+ `detectDarkMode()`（1 进程），总计 8~12 个阻塞进程。

虽然 WiFi 服务名/设备名的缓存减少了 3~4 次 fork，但整体菜单点击仍卡顿 1~2 秒。上轮报告建议的"后台轮询 + 缓存读取"方案未实施。

**建议**：将 `updateNetworkStatusCache()` 移到后台定时器（如每 5 秒刷新一次），菜单回调只读取缓存：

```lua
-- 后台刷新
timer.doEvery(5, updateNetworkStatusCache)
-- 首次立即刷新
updateNetworkStatusCache()

-- 菜单回调读缓存
M.menuBarItem:setMenu(function()
    return menuBuilder.buildNetworkStatusMenuItems(cachedNetworkStatus)
end)
```

**2. `detectDarkMode()` 每次菜单点击都 fork `defaults read`**

`menu_builder.lua:6-14` 每次调用都执行 `io.popen("defaults read -g AppleInterfaceStyle")`。系统外观模式极少变化。

**建议**：缓存结果，用 `hs.distributednotifications` 监听 `AppleInterfaceThemeChangedNotification` 或在 WiFi watcher 触发时刷新。

#### P1 — 代码质量

**3. force-apply 回调仍与 `applyNetworkStrategy` 有大量重复**

`init.lua:147-234` 的 force-apply 回调（约 90 行）仍然复制了 `network_apply.lua` 中 `applyNetworkStrategy()` 的 manual/dhcp 分支逻辑（IPv6 配置 → `runWithSudo` → `waitForCondition` → DNS → 弹窗）。

**建议**：在 `network_apply.lua` 中提取公共函数：

```lua
function M.applyConfigToInterface(wifiInterface, setting, callback)
    -- 公共的 manual/dhcp 设置 + waitForCondition + callback
end
```

`applyNetworkStrategy()` 和 force-apply 回调都调用这个函数，只是传入不同的 setting 来源和 callback。

**4. WebView 模板仍从磁盘重复读取**

`web_view.lua` 中 `loadTemplate("popups.html")` 在以下位置被调用：
- `showPopup()` 第 165 行
- `clear_log` handler 第 238 行
- `refresh_log` handler 第 259 行

`loadTemplate("editor.html")` 在 `showEditor()` 第 44 行。模板内容在模块生命周期内不变。

**建议**：模块加载时缓存：

```lua
local editorTemplate = loadTemplate("editor.html")
local popupsTemplate = loadTemplate("popups.html")
```

**5. `buildNetworkReport()` 重复调用 `getCurrentWiFiStatus()`**

`network_apply.lua:42` 的 `showNetworkReport(ssid)` 调用 `getCurrentWiFiStatus()` 获取 SSID，然后第 61 行调 `buildNetworkReport()` 又在第 11 行调了一次。

**建议**：`buildNetworkReport` 接受可选的 status 参数。

**6. i18n 仍有重复键**

`i18n.lua:25` `log_log_cleared` 与 `i18n.lua:27` `log_cleared` 值完全相同。
`i18n.lua:26` `log_recent_system_logs` 与 `i18n.lua:28` `recent_system_logs` 值完全相同。

**建议**：统一为 `log_cleared` 和 `recent_system_logs`，删除 `log_log_cleared` 和 `log_recent_system_logs`。

**7. i18n 缺失键**

- `init.lua:118` 使用 `i18n.t("log_manual_detect")`，但 `i18n.lua` 中**没有定义**这个键。运行时 `t()` 会返回原始字符串 `"log_manual_detect"` 而非翻译文本。
- `init.lua:233` 使用 `i18n.t("log_force_apply_no_data")`，同样**未在 i18n.lua 中定义**。

**建议**：在 `i18n.lua` 的 zh 和 en 字典中补充这两个键。

**8. `core.lua` 日志仍有硬编码中文**

`core.lua:19,23,30,34,35`：`"驱动层执行"`、`"命令执行失败: 无法打开进程"`、`"命令输出"`、`"错误信息"` 未走 i18n。

#### P2 — 细节

**9. `modulePath` 在 4 个文件中重复计算**

`init.lua:18`、`config.lua:9`、`utils.lua:3`、`web_view.lua:18` 各自 `debug.getinfo(1).source:match(...)`。

**建议**：`utils.lua` 导出 `M.modulePath`，其他文件 `require("wifi_autoconfig.utils").modulePath`。

**10. `init.lua` 有 3 个未使用的 require**

```lua
local notify = require("hs.notify")         -- 未使用，notify 在 network_apply.lua 中 require
local styledtext = require("hs.styledtext") -- 第 96 行有使用（菜单项 styledtext）
local dialog = require("hs.dialog")         -- 第 180 行有使用（blockAlert）
```

实际上 `notify` 是唯一确实未使用的（已移到 `network_apply.lua`），可以删除。`styledtext` 和 `dialog` 在 init.lua 中仍有引用。

**11. `core.lua:2` 未使用的 `hs.network` require**

```lua
local wifi = require("hs.wifi")
-- 没有 require("hs.network")，但上轮报告提到过
```

实际检查发现新版 core.lua 第 2 行只有 `local wifi = require("hs.wifi")`，没有 `hs.network`。这个问题已不存在。

**12. force-apply 的 configSource 语义**

`init.lua:202` 和 `225`：force-apply 成功后用 `config_source_custom`（"自定义策略"）作为报告来源，但实际是编辑器临时配置，应该用 `config_source_editor`（"编辑器临时配置"）。

---

### 设计优点（本轮新增 / 确认保留）

- **架构拆分合理**：`menu_builder.lua` 和 `network_apply.lua` 的抽取使 init.lua 回归纯编排角色，262 行非常紧凑
- **`escapeJS()` 实现完善**：转义顺序正确（先 `\\` 再 `'`/`"`），覆盖了 `\n`/`\r`/`\t`，对 JSON 和纯文本都安全
- **pcall 保护 JSON 解码**：config.lua 的 `save_wifi_scene` 和 `delete_wifi_scene` 都有 `pcall(json.decode, ...)` 保护
- **`handleForceApply` 抽取**：config.lua 中两个 force-apply URL handler 共享解码逻辑
- **`cleanOldLogs()` 续行过滤**：`lastEntryWithinRange` 标记正确处理了无时间戳行的归属
- **启动流程精简**：移除重试机制，依赖 WiFi watcher 后续触发，代码量大幅减少

---

### 修复优先级总览

| 优先级 | 项目 | 改动量 | 影响 |
|--------|------|--------|------|
| **P0** | 菜单栏缓存化（后台 `timer.doEvery` + 菜单读缓存） | ~15 行 | 菜单点击从 1~2s → 瞬时 |
| **P0** | `detectDarkMode()` 缓存 | ~5 行 | 菜单减少 1 次 fork |
| **P1** | i18n 补充缺失键 + 删除重复键 | ~10 行 | 修复翻译缺失 |
| **P1** | 模板缓存 | ~5 行 | 减少磁盘 IO |
| **P1** | 抽取 `applyConfigToInterface()` 公共函数 | ~50 行重构 | 消除 ~90 行重复 |
| **P2** | `modulePath` 统一 / 删除未使用 require / configSource 语义 | ~10 行 | 代码整洁度 |
| **P2** | core.lua 日志国际化 | ~15 行 | 一致性 |

**推荐**：P0 的两个缓存改动加起来不到 20 行，效果最直接。P1 的 i18n 修复（补键 + 删重复）也是几行改动就能修复翻译缺失。force-apply 的公共函数提取改动较大，可以作为后续迭代。
