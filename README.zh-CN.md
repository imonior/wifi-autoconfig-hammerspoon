[English](README.md) | [简体中文](README.zh-CN.md)

# Wi-Fi AutoConfig for Hammerspoon

> 一款基于 Hammerspoon 构建的高性能、全异步的 macOS 网络自动切换工具。

根据当前连接的 Wi-Fi SSID 自动切换网络配置（静态 IP / DHCP / 自定义 DNS / IPv6）。实时检测 SSID 变化，并在数秒内应用匹配的配置方案。

## 功能特性

- **基于 SSID 的自动切换** — `hs.wifi.watcher` 监听 SSID 变化，并即时应用匹配的网络配置
- **每个 SSID 独立配置** — 每个 Wi-Fi 网络都拥有独立的静态 IP、子网掩码、网关、DNS 和 IPv6 设置
- **静态 IP 与 DHCP 两种模式** — `"manual"` 静态绑定，`"dhcp"` 动态获取（可附带自定义 DNS）
- **IPv6 控制** — 每个网络可设为 `automatic`（自动）、`manual`（手动）或 `off`（关闭）
- **全局回退策略** — `__DEFAULT__` 配置应用于任何未单独配置的 SSID
- **编辑器强制应用** — 将编辑器内容直接应用到网络接口而无需保存，并弹窗确认完整配置详情
- **WebView 配置编辑器** — 内置 HTML/CSS 界面管理网络配置，并实时同步硬件状态
- **菜单栏集成** — 快捷访问设置、日志、DHCP 重置与强制重新检测
- **自绘状态面板** — 菜单栏状态视图改为自绘的无边框 WebKit 面板，使用固定的深色底色，因此琥珀色/绿色段标题在浅色与深色模式下都清晰可读，且信息行在悬停时不会高亮（若 webview 创建失败会自动回退到原生菜单）
- **中英双语** — 通过 `hs.host.locale` 自动检测系统语言
- **7 天日志轮转** — 自动清理超过 7 天的日志条目
- **开机自动应用** — Hammerspoon 加载时，以重试逻辑（5 次、间隔 1 秒）应用当前 SSID 的配置，等待 Wi-Fi 就绪
- **配置校验** — 保存时校验 IP/子网掩码/网关/DNS 格式，防止产生损坏的网络设置

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash
```

### 国内镜像加速

如果直连 GitHub 较慢，可使用代理镜像一键安装：

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash
```

更新时同样加上代理前缀：

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash -s -- --update
```

也可以通过环境变量或 `--proxy` 参数指定任意代理：

```bash
# 环境变量方式
GITHUB_PROXY=https://ghfast.top/ bash install.sh

# 命令行参数方式
bash install.sh --proxy https://ghfast.top/
```

该脚本会：
1. 若未安装则先安装 Hammerspoon（通过 Homebrew 或直接下载）
2. 下载项目压缩包并安装到 `~/.hammerspoon/wifi_autoconfig/`
3. 向 `~/.hammerspoon/init.lua` 注入 `require("wifi_autoconfig.init")`（幂等）
4. 重载 Hammerspoon
5. 可选：为 `/usr/sbin/networksetup` 配置免密 sudo，使网络切换不再弹密码框

## 更新

```bash
curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash -s -- --update
```

或本地执行：

```bash
bash scripts/install.sh --update
```

更新会保留你的 `config.json`（更新时备份为 `config.json.backup`）。

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/uninstall.sh | bash
```

国内镜像：

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/uninstall.sh | bash
```

或本地执行：

```bash
bash scripts/uninstall.sh              # 交互式（询问是否备份配置）
bash scripts/uninstall.sh --force      # 跳过询问，自动备份配置到 ~/.wifi_autoconfig_backups/
```

卸载器在移除模块前会将 `config.json` 备份到 `~/.wifi_autoconfig_backups/wifi_autoconfig_config_backup.json`。可通过 `BACKUP_DIR` 环境变量修改备份位置。Hammerspoon 本身不会被卸载。

## 从旧版本迁移

本项目早期以旧名称发布（安装目录为 `~/.hammerspoon/wifi_ip_switcher` 或 `~/.hammerspoon/wifi_ip_controller`）。v3.0.0 是一次全新起点，因此安装器**不会**自动迁移旧数据。

如果你装过旧版本，请运行专门的旧版升级脚本。它会把每个旧目录的 `config.json` 分别备份到 `~/.wifi_autoconfig_backups/`（每个旧目录一个文件），删除旧模块及其在 `init.lua` 中的引用，然后一步到位地启动 v3.0.0 安装器：

```bash
bash scripts/legacy-install.sh            # 交互式（清理前询问）
bash scripts/legacy-install.sh --force    # 跳过清理询问
```

如果你只想彻底卸载旧版、不安装 v3.0.0，请使用：

```bash
bash scripts/legacy-uninstall.sh            # 交互式
bash scripts/legacy-uninstall.sh --force    # 跳过询问
```

## 离线安装（发布包）

每次发布都会提供一个自包含的归档文件 `wifi-autoconfig-hammerspoon-vX.Y.Z.zip`，
内含全部脚本与源文件，可在无法访问 GitHub 的机器上安装：

1. 从发布页下载 `wifi-autoconfig-hammerspoon-vX.Y.Z.zip`。
2. 解压：
   ```bash
   unzip wifi-autoconfig-hammerspoon-vX.Y.Z.zip
   cd wifi-autoconfig-hammerspoon
   ```
3. 在解压后的目录内运行安装器。它会自动识别本地打包文件并离线安装，无需联网：
   ```bash
   bash scripts/install.sh
   ```

如需自行构建归档（仅需 `zip`/`tar`，无需联网）：

```bash
bash scripts/build-release.sh
# 生成 dist/wifi-autoconfig-hammerspoon-vX.Y.Z.zip 与 release.html
```

## 手动安装

1. 安装 [Hammerspoon](https://hammerspoon.org)
2. 将项目文件复制到 `~/.hammerspoon/wifi_autoconfig/`：
   ```bash
   mkdir -p ~/.hammerspoon/wifi_autoconfig/ui/templates ~/.hammerspoon/wifi_autoconfig/ui/icons
   cp src/*.lua ~/.hammerspoon/wifi_autoconfig/
   cp src/ui/*.lua ~/.hammerspoon/wifi_autoconfig/ui/
   cp src/ui/templates/*.html ~/.hammerspoon/wifi_autoconfig/ui/templates/
   cp src/ui/icons/*.svg ~/.hammerspoon/wifi_autoconfig/ui/icons/
   cp config.example.json ~/.hammerspoon/wifi_autoconfig/config.json
   ```
3. 在 `~/.hammerspoon/init.lua` 中添加：
   ```lua
   -- ~/.hammerspoon/init.lua
   require("wifi_autoconfig.init")
   ```
4. 重载 Hammerspoon（菜单栏图标 → Reload Config，或在控制台执行 `hs.reload()`）

### 开机自动打开编辑器

默认情况下，模块在后台静默运行。如需在 Hammerspoon 加载时自动打开配置编辑器，可在 [init.lua](init.lua) 的 `M.init()` 末尾添加：

```lua
hs.timer.doAfter(2, function()
    config.read()
    ui.showEditor(config.current)
end)
```

## 工作原理

### 自动切换流程

1. `hs.wifi.watcher` 检测到 SSID 变化 → 触发 `performNetworkAudit()`
2. 查找新 SSID 的配置（依次回退到 `__DEFAULT__`、纯 DHCP）
3. 通过 `networksetup` 命令并使用 sudo 应用网络设置：
   - IPv4：`networksetup -setmanual` / `-setdhcp`
   - IPv6：`networksetup -setv6manual` / `-setv6automatic` / `-setv6off`
   - DNS：`networksetup -setdnsservers`（留空 = 恢复为 DHCP 自动 DNS）
4. 通过 `waitForCondition()` 轮询验证 IP/DNS 是否真正生效
5. 发送 macOS 通知并弹窗展示完整的网络报告

### 配置来源类型

| 来源 | 触发时机 |
|------|----------|
| 自定义策略 | SSID 在 `config.json` 中有专属配置 |
| 全局回退 | SSID 未配置，应用 `__DEFAULT__` |
| DHCP 自动 | 完全没有配置，回退到系统 DHCP |
| 编辑器临时配置 | 从编辑器强制应用且不保存 |

### 菜单栏功能

| 菜单项 | 作用 |
|--------|------|
| 打开设置 | 打开 WebView 配置编辑器 |
| 查看日志 | 在弹窗中显示最近的日志条目 |
| 将当前网络设为 DHCP | 立即将当前接口重置为 DHCP + 自动 DNS |
| 强制网络检测 | 关闭编辑器、清空 SSID 缓存并重新执行网络审计 |

## 配置

编辑 `~/.hammerspoon/wifi_autoconfig/config.json`，或使用内置编辑器（菜单栏图标 → 打开设置）。

### 配置字段

| 字段 | 说明 |
|------|------|
| `mode` | `"dhcp"` 或 `"manual"` |
| `ip` | IPv4 地址（手动模式） |
| `netmask` | 子网掩码（默认：`255.255.255.0`） |
| `gateway` | 网关 IP（手动模式） |
| `dns` | DNS 服务器，逗号分隔。留空 = DHCP 自动 |
| `v6mode` | `"automatic"`、`"manual"` 或 `"off"` |
| `ipv6` | IPv6 地址（手动模式） |
| `v6prefix` | IPv6 前缀长度（默认：`64`） |
| `v6gateway` | IPv6 网关（手动模式） |

### 示例

```json
{
  "__DEFAULT__": {
    "mode": "dhcp",
    "dns": "",
    "v6mode": "automatic"
  },
  "MyHomeWiFi": {
    "mode": "dhcp",
    "dns": "127.0.0.1",
    "v6mode": "off"
  },
  "Office_5G": {
    "mode": "manual",
    "ip": "192.168.1.100",
    "netmask": "255.255.255.0",
    "gateway": "192.168.1.1",
    "dns": "192.168.1.1,8.8.8.8",
    "v6mode": "off"
  }
}
```

## 项目结构

模块采用**表现层与核心逻辑分离**的架构，表现层与核心逻辑完全解耦，以获得更好的性能与可维护性：

```
wifi-autoconfig-hammerspoon/
├── CHANGELOG.md              # 版本历史（英文）
├── CHANGELOG.zh-CN.md        # 版本历史（中文）
├── scripts/                  # 安装脚本
│   ├── install.sh            # 一键安装脚本（--update / --force / --help）
│   ├── uninstall.sh          # 卸载脚本（--force）
│   ├── legacy-install.sh    # 一步升级：清理旧版后安装 v3.0.0
│   └── legacy-uninstall.sh   # 一次性彻底卸载旧版
├── config.example.json       # 示例配置模板
├── src/                      # 源代码目录
│   ├── init.lua              # 模块总指挥官（入口）：菜单栏、Wi-Fi 监听、自动切换、开机审计
│   ├── core.lua              # 核心驱动层：sudo networksetup、Wi-Fi 状态、RSSI、DNS、IPv6
│   ├── config.lua            # 数据持久化层：配置持久化 + hs.urlevent 处理器 + 校验
│   ├── utils.lua             # 工具函数集：日志（7 天轮转）、异步等待/轮询、HTML 转义
│   ├── i18n.lua              # 国际化：中/英翻译，通过 hs.host.locale 自动检测
│   ├── menu_builder.lua      # 菜单栏构建器：菜单栏构建 + 深色模式检测
│   ├── network_apply.lua     # 网络配置应用：网络配置应用逻辑
│   └── ui/                   # 表现层
│       ├── web_view.lua      #   WebView 控制器：窗口生命周期、编辑器 + 弹窗管理
│       └── templates/        #   纯前端模板
│           ├── editor.html   #     配置编辑器面板（完整的 UI/交互/CSS）
│           └── popups.html   #     多用途弹窗（复用为日志查看器 + 成功通知）
```

### 各层职责

- **表现层**（`ui/`）：WebView 窗口与 HTML 模板。编辑器在运行时将配置 JSON 和网络列表注入 HTML，通过 `hs.urlevent` URL 方案回传（`hammerspoon://save_wifi_scene`、`hammerspoon://force_apply_network` 等）。
- **核心逻辑**（`core.lua`）：所有通过 `networksetup`（配合 sudo）执行的网络操作，使用 `shellQuote()` 进行安全的参数转义。Wi-Fi 状态检测使用 `hs.wifi.currentNetwork()` 获取 SSID，`hs.wifi.interfaceDetails()` 获取 RSSI（以 `system_profiler SPAirPortDataType` 作为回退）。
- **数据层**（`config.lua`）：基于 JSON 的配置，保存时校验 IPv4/DNS 格式。配置文件位于 `~/.hammerspoon/wifi_autoconfig/config.json`。
- **工具函数**（`utils.lua`）：异步辅助函数 — `waitForCondition()` 以可配置的超时/间隔进行轮询，`executeWithRetry()` 用于重试逻辑。日志文件自动轮转 7 天前的条目。

所有网络操作均使用 `hs.timer.doAfter` **全异步**执行，无任何阻塞调用。

## 环境要求

- macOS 13+（已在 macOS 15 Sequoia 上测试）
- Hammerspoon 0.4.3+
- sudo 权限（用于 `networksetup` 命令 — 安装器可配置免密 sudo，否则首次使用时 Hammerspoon 会提示输入密码）
- 定位服务权限（可选，用于显示 Wi-Fi RSSI 信号强度）

## 常见问题

**Sudo 提示**：模块使用 `sudo /usr/sbin/networksetup` 修改网络设置。安装时安装器可选择性写入免密 sudoers 规则到 `/etc/sudoers.d/hammerspoon_netconfig`，使网络切换静默执行、不再弹密码框。若跳过该步骤（或本机无此规则），可手动配置：运行 `sudo visudo -f /etc/sudoers.d/hammerspoon_netconfig` 并添加 `<你的用户名> ALL=(ALL) NOPASSWD: /usr/sbin/networksetup`。

**RSSI 显示为 Unknown**：macOS 15+ 需要定位服务权限才能获取 Wi-Fi 信号信息。进入「系统设置 → 隐私与安全性 → 定位服务」→ 启用 Hammerspoon。若不可用，弹窗将隐藏信号行。

**开机配置未生效**：模块在 Hammerspoon 加载后会重试 5 次（间隔 1 秒）等待 Wi-Fi 连接。通过菜单栏 → 查看日志，检查 `runInitialAudit` 相关条目。

**日志文件位置**：`~/.hammerspoon/wifi_autoconfig/wifi_autoconfig.log`（超过 7 天的条目会自动清理）

## 许可证

MIT