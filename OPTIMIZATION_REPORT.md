## Wi-Fi AutoConfig for Hammerspoon v2 优化分析报告（2026-07-24 更新）【历史文档】

> **⚠️ Historical document — last updated 2026-07-24.** This report reflects the codebase state at v2 and is superseded by subsequent releases (v3.0.0+). Most issues listed here have been addressed in later iterations. See [CHANGELOG.md](CHANGELOG.md) for current status.

基于项目重构后的最新版本（`src/` + `scripts/` 目录结构、菜单栏 VPN 状态显示、SVG 图标、编辑器 i18n 等新增功能）。以下分析覆盖全部 18 个源文件，聚焦新版引入的新问题以及仍存在的旧问题。

---

### 架构概览

项目从扁平结构重组为 `src/` + `scripts/` 分层，新增 VPN/Tunnel 检测、styled-text 菜单栏、SVG 图标等功能。代码量从约 1200 行增长到约 2200 行（Lua 部分），HTML 模板从 31KB 增长到 35KB。整体 4 层架构（init → core → config → ui）依然清晰，但 init.lua 和 core.lua 的体量膨胀带来了新问题。

---

### P0 — 严重性能问题

**1. 菜单栏点击时的进程风暴（新增 · 关键）**

`buildNetworkStatusMenuItems()` 是一个新增函数（init.lua:203-349），在用户每次点击菜单栏图标时同步执行。它触发以下阻塞调用链：

```
buildNetworkStatusMenuItems()
├── getCurrentWiFiStatus()        → getWiFiDevice() + networksetup -getairportpower + networksetup -getairportnetwork + system_profiler = 2~4 进程
├── getWiFiServiceName()          → networksetup -listallnetworkservices           = 1 进程
├── getCurrentIPv4Info()          → networksetup -getinfo                          = 1 进程
├── getCurrentIPv6Info()          → networksetup -getinfo + ifconfig               = 1~2 进程
├── getActiveDNS()                → getWiFiServiceName() + networksetup -getdnsservers = 2 进程
├── getVPNInfo()                  → getWiFiDevice() + ifconfig + scutil --nc list + N×scutil --nc status + ls = 3~5+ 进程
└── defaults read AppleInterfaceStyle                                               = 1 进程
```

**单次菜单点击产生 11~16 个阻塞进程**，用户感知到 1~3 秒的菜单卡顿。其中 `getVPNInfo()` 单独贡献了 3~5+ 次 `io.popen`（`ifconfig` 全量输出解析 + `scutil --nc list` + 每个 VPN 各一次 `scutil --nc status`）。这是目前用户体验最大的痛点。

**建议**：将网络状态信息收集改为后台异步轮询，菜单栏只做缓存数据的展示：

```lua
local cachedMenuData = {}

-- 后台定时刷新（每 3~5 秒），或在 WiFi watcher 触发时刷新
local function refreshMenuCache()
    cachedMenuData.status = core.getCurrentWiFiStatus()
    cachedMenuData.ipv4 = { core.getCurrentIPv4Info(cachedMenuData.wifiInterface) }
    cachedMenuData.vpn = core.getVPNInfo()
    -- ...
end

-- 菜单回调只读缓存
M.menuBarItem:setMenu(function()
    return buildMenuFromCache(cachedMenuData)
end)
```

这样菜单点击就是瞬时响应，而数据刷新在后台异步进行。

**2. `getWiFiServiceName()` / `getWiFiDevice()` 无缓存（延续 · 高影响）**

这两个值在硬件不变的情况下是固定的，但每次调用都 fork 进程。在新版中调用频率更高——`buildNetworkStatusMenuItems()` 每次点击菜单至少调 3 次（直接 1 次 + `getActiveDNS()` 内部 1 次 + `getVPNInfo()` 内部 1 次）。

**建议**：首次调用后缓存，整个模块生命周期复用：

```lua
local _wifiServiceName, _wifiDevice

function M.getWiFiServiceName()
    if _wifiServiceName then return _wifiServiceName end
    -- ... 原有逻辑 ...
    _wifiServiceName = line
    return line
end
```

仅这一个改动就能将每次菜单点击的进程数减少 3~4 个。

**3. `getActiveDNS()` 内部硬编码调 `getWiFiServiceName()`（延续）**

第 204 行 `local wifiInterface = M.getWiFiServiceName()` 导致每次调用都多 fork 一次。在 init.lua 中多处已经持有 `wifiInterface`（如 `buildNetworkStatusMenuItems` 第 205 行），但无法传给 `getActiveDNS()`。

**建议**：添加可选参数 `function M.getActiveDNS(wifiInterface)`，默认回退到 `M.getWiFiServiceName()`。

---

### P1 — 架构与代码质量

**4. `init.lua` 膨胀到 590 行 — 需要拆分**

`init.lua` 承担了太多职责：菜单栏构建（含 styled-text 渲染 150 行）、网络策略应用（80 行）、force-apply 流程（90 行）、WiFi watcher、启动审计、URL scheme 注册。其中 `buildNetworkStatusMenuItems()` 和 force-apply 回调各自是独立的功能域，完全应该独立出去。

**建议**：

```
src/
├── init.lua              -- 精简为纯编排层（~200 行）
├── core.lua              -- 不变
├── config.lua            -- 不变
├── menu_builder.lua      -- 新增：buildNetworkStatusMenuItems + 颜色方案 + 暗色模式检测
├── network_apply.lua     -- 新增：applyConfigToInterface() 公共函数
└── ui/web_view.lua       -- 不变
```

`network_apply.lua` 提取 `applyNetworkStrategy()` 和 force-apply 回调的公共逻辑（约 90 行重复代码），两者共用同一个 `applyConfigToInterface(wifiInterface, setting, callback)` 函数。

**5. `getVPNInfo()` 是最大单体函数（165 行）— 应拆分**

`core.lua:253-417` 的 VPN 检测逻辑包含 4 个独立步骤：ifconfig 解析、scutil VPN 枚举、WireGuard 检测、剩余 tunnel 接口扫描。这些步骤相互独立，可以拆成内部 helper：

```lua
local function parseIfconfigInterfaces()  -- 返回 ifaceDetails table
local function getScutilVPNs(ifaceDetails) -- 返回 scutilVPNs array
local function getWireGuardMappings()      -- 返回 wgInterfaceMap table
local function getRemainingTunnels(ifaceDetails, wgInterfaceMap) -- 返回 otherIfaces
```

这样 `getVPNInfo()` 本体就变成一个 10 行的编排函数，每个子步骤可以独立测试。

**6. `force_apply_network` 和 `force_apply_network_with_confirm` URL handler 完全重复**

`config.lua:142-162` 的两个 `urlevent.bind` 回调代码完全相同（逐字节一致），只是 URL 路径不同。前端 editor.html 只调用了 `force_apply_network_with_confirm`，`force_apply_network` 从未被使用。

**建议**：删除 `force_apply_network` handler（如果确认无其他调用方），或将两者合并为一个。

**7. WebView 模板每次从磁盘读取（延续）**

`web_view.lua` 的 `showPopup()` 每次调用 `loadTemplate("popups.html")`（125 行/4KB），`showEditor()` 每次读 `editor.html`（703 行/27KB）。在模块生命周期内模板内容不变。

**建议**：模块加载时缓存：

```lua
local editorTemplate = loadTemplate("editor.html")
local popupsTemplate = loadTemplate("popups.html")
```

`clear_log` 和 `refresh_log` handler（web_view.lua:230-269）也各自 `loadTemplate("popups.html")`，共 2 次额外磁盘读取，同样受益于缓存。

**8. `refreshEditor()` JS 注入存在转义风险（延续）**

```lua
-- web_view.lua:113
local jsExpr = string.format("refreshConfig('%s', '%s')", 
    networksJson:gsub("'", "\\'"), configJson:gsub("'", "\\'"))
```

如果 SSID 名包含反斜杠（如 `Corp\Network`），`gsub` 产生的 `\\'` 在 JS 上下文中会断开字符串边界。

**建议**：直接传 JSON 对象，绕过字符串转义：

```lua
local jsExpr = string.format("refreshConfig(%s, %s)", 
    json.encode(preferredNetworks), json.encode(config.current))
```

**9. `core.lua` 的日志仍有硬编码中文**

`core.lua:17,21,28,32` 的日志消息（`"驱动层执行"`、`"命令执行失败"`、`"无法打开进程"`）未走 i18n 系统。

**10. i18n 中重复的翻译键**

`log_cleared` 与 `log_log_cleared` 值完全相同，`log_recent_system_logs` 与 `recent_system_logs` 也是。应合并为单一 key。

---

### P2 — 细节与一致性

**11. 暗色模式检测每次 fork `defaults read`**

`init.lua:215-220` 每次构建菜单时调用 `io.popen("defaults read -g AppleInterfaceStyle")`。系统外观模式极少变化。

**建议**：缓存结果，在 `hs.screen.watcher` 回调中刷新（或用 `hs.distributednotifications` 监听 `AppleInterfaceThemeChangedNotification`）。

**12. `modulePath` 在 4 个文件中重复计算**

`init.lua:17`、`config.lua:9`、`utils.lua:3`、`web_view.lua:17` 各自 `debug.getinfo(1).source:match(...)`。

**建议**：在 `utils.lua` 导出 `M.modulePath`，其他模块引用即可。

**13. `editor.html` 的 `fetchNetworkInfo()` 重试不会提前终止**

```javascript
// editor.html:685-694
function fetchNetworkInfo() {
    callLua('get_current_network_info');
    retryCount++;
    if (retryCount < maxRetries) {
        setTimeout(fetchNetworkInfo, retryInterval);
    }
}
```

即使第一次就成功获取到网络信息，仍会继续重试 4 次（共 5 次 `get_current_network_info` 事件）。

**建议**：在 `updateCurrentNetworkUI()` 中设置标记，`fetchNetworkInfo()` 检测到标记后停止重试。

**14. `buildNetworkReport` 与 `showNetworkReport` 重复调用 `getCurrentWiFiStatus()`**

`showNetworkReport()` 第 54 行调一次，`buildNetworkReport()` 第 23 行又调一次。

**建议**：`buildNetworkReport` 接受可选的 `status` 参数。

**15. `cleanOldLogs()` 在 `log()` 中同步执行**

每 7 天触发一次完整日志文件读取 + 重写，在 `log()` 调用路径上阻塞。

**建议**：`hs.timer.doAfter(0, cleanOldLogs)` 异步化。

**16. README 的 Project Structure 与实际目录不匹配**

README 仍展示旧的扁平目录结构，未反映 `src/` + `scripts/` 的重构，也未包含新增的 `menu_builder` 功能、VPN 检测、SVG 图标等。

---

### 现有设计的优点（值得保留）

- **全局锚定 `_G.WificonfigModule`**：有效防止 Lua GC 回收菜单栏回调
- **VPN/Tunnel 全覆盖检测**：macOS VPN (scutil) + WireGuard + 通用 tunnel，覆盖面广
- **styled-text 菜单栏**：暗色/亮色模式自适应，信息密度高
- **`showPopup` 的延迟重建**：用 `hs.timer.doAfter(0.1)` 避免 delete-then-create 的 WebKit 竞态
- **编辑器客户端 i18n**：HTML 模板内嵌双语字典，通过 `%LOCALE_PLACEHOLDER%` 自动切换
- **安装脚本代理支持**：`GITHUB_PROXY` 环境变量 + `--proxy` 参数，国内用户友好
- **`shellQuote()` 安全转义**：正确处理单引号嵌套
- **配置迁移**：从旧文件名自动迁移，用户体验好

---

### 实施优先级建议

| 优先级 | 项目 | 改动范围 | 预期效果 |
|--------|------|----------|----------|
| **P0-1** | 菜单栏缓存化（后台轮询 + 菜单读缓存） | init.lua | 菜单点击从 1~3s → 瞬时 |
| **P0-2** | 缓存 `getWiFiServiceName()` / `getWiFiDevice()` | core.lua（6 行改动） | 每次操作减少 3~4 次 fork |
| **P0-3** | `getActiveDNS()` 接受可选接口参数 | core.lua + init.lua | 每次操作减少 1~2 次 fork |
| **P1-1** | 拆分 init.lua（menu_builder + network_apply） | init.lua → 3 文件 | 代码可维护性 |
| **P1-2** | 拆分 `getVPNInfo()` 为 4 个 helper | core.lua | 可测试性 + 可读性 |
| **P1-3** | 删除重复 URL handler / 模板缓存 / JS 转义修复 | config.lua + web_view.lua | 减少 ~50 行 + 修复潜在 bug |
| **P1-4** | i18n 清理 + core.lua 日志国际化 | i18n.lua + core.lua | 一致性 |
| **P2** | 暗色模式缓存 / modulePath 统一 / 重试终止 / README 更新 | 多文件 | 细节完善 |
| **远期** | `runWithSudo` → `hs.task` 异步化 | core.lua 全面重构 | 消除事件循环阻塞 |

**推荐实施路径**：先做 P0-2（6 行改动，立即见效）→ P0-3（5 行改动）→ P0-1（中等改动，解决最大痛点）→ P1 重构 → 远期异步化。P0-2 和 P0-3 加起来不到 15 行改动，但能将每次操作的进程数减少 40~50%。
