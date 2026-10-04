[English](README.md) | [简体中文](README.zh-CN.md)

# Wi-Fi AutoConfig for Hammerspoon

> 一款基于 Hammerspoon 构建的 macOS 网络自动切换工具，等待与轮询由定时器驱动，不做阻塞式休眠。

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
- **结果如实反馈** — 收集每个 `networksetup` 调用的返回状态；某步失败时（例如缺少免密 sudo 规则）弹窗会列出未完成的步骤，而不是宣称成功
- **中英双语** — 通过 `hs.host.locale` 自动检测系统语言
- **7 天日志轮转** — 自动清理超过 7 天的日志条目
- **开机检测** — Hammerspoon 加载时应用一次当前 SSID 的配置，此后每次 Wi-Fi 事件再应用
- **配置校验** — 保存或强制应用之前校验 IPv4、IPv6、子网掩码、网关与 DNS 格式，避免把错误地址写进网卡

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
5. 可选：为 `/usr/sbin/networksetup` 配置免密 sudo，使网络切换静默执行——没有这条规则时命令会直接失败而不是弹出密码框，弹窗会列出未完成的步骤

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

它也会清理安装器留在模块目录之外的东西。免密 sudoers 规则文件只有在带有安装器写入的标记行时才会被删除，因此你手动编辑过的文件、或其他工具创建的文件只会被打印出来而不会被删除，旧的文件名也遵循同样的规则。`~/.hammerspoon/init.lua` 里的 `require` 行会在先备份该文件的前提下移除；卸载器认不出的引用只报告、不替你改写。提问走的是 `/dev/tty`，因此 `curl | bash` 不会把脚本自身剩下的内容当成答案读掉。没有终端可用时，卸载器保持安全默认行为（`config.json` 仍然先备份），随后说明原因并停下，而不是替你回答最终的确认。

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

版本号取自 `scripts/install.sh` 里的 `MODULE_VERSION`，并且只有在存在与之匹配的 git 标签时脚本才肯构建：一个命名为 v3.2.1、却没有 v3.2.1 标签（或标签来自另一个提交）的压缩包，正是发布页指向错误代码的方式。当匹配的标签不在当前提交上时脚本会给出警告；构建结束时还会提示生成的 `release.html` / `RELEASE.md` 与仓库中已提交的版本是否存在差异。

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
2. 查找新 SSID 的配置（依次回退到 `__DEFAULT__`、纯 DHCP；若 `config.json` 无法解析则跳过本次切换）
3. 通过 `networksetup` 命令并使用 sudo 应用网络设置：
   - IPv4：`networksetup -setmanual` / `-setdhcp`
   - IPv6：`networksetup -setv6manual` / `-setv6automatic` / `-setv6off`
   - DNS：`networksetup -setdnsservers`（留空 = 恢复为 DHCP 自动 DNS）
4. 通过 `waitForCondition()` 轮询验证 IP/DNS 是否真正生效
5. 发送 macOS 通知并弹窗展示完整的网络报告，其中列出所有未完成的步骤（列表非空时标题改为「网络配置仅部分生效」）

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
| 强制网络检测 | 清空已记住的 SSID 并立即重新执行网络审计 |

## 配置

编辑 `~/.hammerspoon/wifi_autoconfig/config.json`，或使用内置编辑器（菜单栏图标 → 打开设置）。

### 配置字段

| 字段 | 说明 |
|------|------|
| `mode` | `"dhcp"` 或 `"manual"`，保存时校验，应用之前再校验一次。旧版本保存的、缺少 `mode` 字段的条目按 `dhcp` 读取 |
| `ip` | IPv4 地址（手动模式） |
| `netmask` | 子网掩码（默认：`255.255.255.0`） |
| `gateway` | 网关 IP，手动模式必填：`-setmanual` 把它按位置取参，此前缺失时会被当成字面量 `nil` 下发 |
| `dns` | DNS 服务器，逗号分隔（也可写成 JSON 数组，保存时会归一化为逗号分隔字符串）。留空 = DHCP 自动 |
| `v6mode` | `"automatic"`、`"manual"` 或 `"off"`。缺省或留空 = 保持 IPv6 现状不变；只有 `"off"` 会关闭 IPv6；其他取值在执行任何命令之前就会被拒绝 |
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
│   ├── legacy-install.sh    # 一步升级：清理 1.0 之前的旧版后安装当前版本
│   └── legacy-uninstall.sh   # 一次性彻底卸载旧版
├── config.example.json       # 示例配置模板
├── src/                      # 源代码目录
│   ├── init.lua              # 模块总指挥官（入口）：菜单栏、Wi-Fi 监听、自动切换、开机审计
│   ├── core.lua              # 核心驱动层：sudo networksetup、Wi-Fi 状态、IPv4/IPv6、DNS、VPN
│   ├── config.lua            # 数据持久化层：配置持久化 + hs.urlevent 处理器 + 校验
│   ├── utils.lua             # 工具函数集：日志（7 天轮转）、定时器等待/轮询、HTML 转义
│   ├── i18n.lua              # 国际化：中/英翻译，通过 hs.host.locale 自动检测
│   ├── menu_builder.lua      # 菜单行构建：两种界面的状态行 + 深色模式检测
│   ├── panel.lua             # 状态面板：以无边框 WKWebView 取代原生 NSMenu
│   ├── network_apply.lua     # 网络配置应用：网络配置应用逻辑
│   └── ui/                   # 表现层
│       ├── web_view.lua      #   WebView 控制器：窗口生命周期、编辑器 + 弹窗管理
│       └── templates/        #   纯前端模板
│           ├── editor.html   #     配置编辑器面板（完整的 UI/交互/CSS）
│           └── popups.html   #     多用途弹窗（复用为日志查看器 + 成功通知）
```

### 各层职责

- **表现层**（`ui/`、`panel.lua`）：WebView 窗口与 HTML 模板。编辑器在运行时将配置 JSON 和网络列表注入 HTML，通过 `hs.urlevent` URL 方案回传（`hammerspoon://save_wifi_scene`、`hammerspoon://force_apply_network_with_confirm` 等）。`panel.lua` 自行绘制菜单栏的状态列表。
- **核心逻辑**（`core.lua`）：所有通过 `networksetup`（配合 sudo）执行的网络操作，使用 `shellQuote()` 进行安全的参数转义。SSID 取自 `hs.wifi.currentNetwork()`，取不到时回退到 `networksetup -getairportnetwork`；`networksetup -getinfo` 每次读取只执行一次，IPv4 与 IPv6 共用同一份输出解析。
- **数据层**（`config.lua`）：基于 JSON 的配置，保存与强制应用之前都会校验 IPv4/IPv6/子网掩码/网关/DNS 格式，内存里已存好的策略在真正下发之前还会再校验一遍，配置文件位于 `~/.hammerspoon/wifi_autoconfig/config.json`。若该文件无法解析（例如手工编辑漏了个逗号），模块继续使用内存中最后一次成功读取的配置，磁盘上的文件原样保留，并拒绝任何写入直到它重新可解析——因此「读取失败」永远不可能变成「覆盖掉你的全部策略」。此时会弹出模态对话框等待你处理：修好语法后点**重新读取**即可原地重载并立刻恢复写入，无需重载 Hammerspoon。同样的保护也覆盖「策略还装载在内存里，文件却被删除或截成 0 字节」的情形：那被视为一次需要恢复的丢失，而不是「没有策略」。
- **工具函数**（`utils.lua`）：基于定时器的辅助函数 —— `waitForCondition()` 以可配置的超时与间隔轮询，`wait()` 延迟执行回调，`blockAlertOnce()` 只在没有别的对话框正在等答案时才弹出对话框。日志文件自动轮转 7 天前的条目。

网络切换由定时器驱动：应用流程用 `hs.timer` 轮询等待结果（`waitForCondition`），不会让 Hammerspoon 卡在休眠上。两处调用是刻意阻塞的：强制应用前的确认框 `hs.dialog.blockAlert`，以及每个 `io.popen` 命令本身（若 `networksetup` 卡死，会拖住发起它的那个定时器回调——`core.lua` 里有相应说明）。阻塞对话框跑的是嵌套的模态循环，因此所有这些调用都经过同一个闸门：已经有对话框在等待时再次请求的对话框会被跳过并记入日志，而不是叠在一个无法点掉的窗口之上。若你在一轮应用还没等完时又切换了网络，这一轮会被丢弃而不是继续：每轮应用都带着一个令牌，被取代的那一轮不再往一块已经换到别的网络的网卡上写 DNS 或 IPv6。

## 环境要求

- macOS 13+（已在 macOS 15 Sequoia 上测试）
- Hammerspoon 0.4.3+
- **辅助功能 / 输入监控权限** — 模块使用 `hs.eventtap` 检测 WebView 配置编辑器何时获得焦点，以便键盘快捷键（⌘S 保存、⌘W 关闭）能够正常工作。没有该权限时编辑器仍然可以打开，但这些快捷键不会响应。请在**系统设置 → 隐私与安全性 → 辅助功能**或**输入监控**中授予访问权限，然后重新加载 Hammerspoon。
- `networksetup` 所需的 sudo 权限。安装器可为**当前账户单独**写入免密 sudoers 规则；没有该规则时网络变更不会提示输密码，而是直接失败（见常见问题）。

## 常见问题

**切换网络后什么都没变**：模块通过 `sudo /usr/sbin/networksetup` 修改网络设置，而 `io.popen` 不会给 sudo 分配终端，所以缺少 sudoers 规则时并不会弹出密码框——命令直接失败，结果弹窗会列出未完成的步骤。安装时安装器可在 `/etc/sudoers.d/hammerspoon_wificonfig` 为**当前账户单独**写入免密规则，刻意不放行给 `%admin`：任何本机进程都能以该管理员身份免密执行 `-setdnsservers`，这是一条比本模块活得更久的 DNS 劫持通道。规则只点名模块用到的子命令（`setmanual`、`setdhcp`、`setdnsservers`、`setv6manual`、`setv6automatic`、`setv6off`、`listallnetworkservices`），而不是放行整个二进制；卸载时 `scripts/uninstall.sh` 会删除它写下的文件。规则文件先写到临时路径，用 `visudo -cf` 校验通过之后才移入原位，因此一次失败的校验不会在 `/etc/sudoers.d` 留下破损的 drop-in；安装器随后还会用免密探测确认这条规则对你的账户确实生效，才报告成功。写入之前它会先征求你的同意；没有终端可供提问时（管道执行的 `curl | bash`）它拒绝写入这条规则，只打印你自己添加时要用到的命令——一份长期有效的授权不该因为没人应答就被创建。

若要自己添加，运行 `sudo visudo -f /etc/sudoers.d/hammerspoon_wificonfig`，把下面这行中的 `<your-user>` 换成你的账户名后加入，并用 `sudo visudo -cf /etc/sudoers.d/hammerspoon_wificonfig` 校验语法：

```
<your-user> ALL=(root) NOPASSWD: /usr/sbin/networksetup -setmanual *, /usr/sbin/networksetup -setdhcp *, /usr/sbin/networksetup -setdnsservers *, /usr/sbin/networksetup -setv6manual *, /usr/sbin/networksetup -setv6automatic *, /usr/sbin/networksetup -setv6off *, /usr/sbin/networksetup -listallnetworkservices *
```

早期版本可能把规则写在 `/etc/sudoers.d/hammerspoon_netconfig` 或 `/etc/sudoers.d/hammerspoon_network`，而 v3.1.0 放行的是整个二进制而非逐条子命令。安装器会查找任何提到 `networksetup` 的 drop-in，打印其完整内容，说明它是否比当前规则更宽（授予了 `%admin` 这类用户组，或没有指定子命令而就放行了整个二进制），并列出它缺少哪些必需子命令。sudo 把多条规则视为可选项的叠加，所以只要那条宽规则还在，无论新文件写得多窄都约束不住权限——因此安装器在新规则验证通过之后，会删除**它自己写下的**遗留文件（凭文件里的标记行识别）。不是它写的文件绝不会被删：内容会打印出来，并告诉你用 `visudo -f` 自行查看。正因为这条遗留规则无论如何都仍然有效，即使某个未标记的宽规则已经让免密探测通过，安装器依然会收窄它自己管理的那份（`hammerspoon_wificonfig`），并且只在确认新授权生效之后才动旧文件；如果你在存在过宽规则时拒绝了添加规则，脚本会明确说明本次没有写入任何东西、更宽的权限仍在生效。对于没有密码就读不到的 drop-in，脚本只报告「无法判断」而不是猜。

**弹窗提示 config.json 无法解析**：模块会停在这里等你处理。你的策略仍然完整保留在该文件里——它只是停止读取，并在重新可解析之前拒绝写入，所以一个漏掉的逗号不会让你丢掉整个文件。修正语法（用 JSON 校验工具，或 `plutil -lint`）后点**重新读取**，文件会立刻被重读，写入与自动切换随之恢复，不需要重载 Hammerspoon。点**稍后处理**则维持在这个安全状态，同样且未再变动的内容不会反复打扰你（文件又出现新的破损时会重新提示）。在此期间自动切换被跳过，而不是降级成 DHCP；从编辑器发起的保存/删除也会被拒绝并单独弹窗告知，内存里不会留下磁盘上并不存在的半份策略。

**弹窗提示 config.json 不见了**：与上一条是同一个安全状态，只是抵达方式不同——模块内存里还装载着策略，文件却被删除或被截成了 0 字节。把它当作「没有策略」意味着一张空的策略表，下一次切换就会因找不到该 SSID 的策略而把网卡强制设为 DHCP，静态网络当场失去地址。因此策略继续留在内存中，写入保持拒绝、自动切换跳过，直到你把文件放回来（从备份恢复，或用它旁边的 `config.json.backup`），之后点**重新读取**即可接管，无需重载 Hammerspoon。点**稍后处理**会保持该状态且不再反复打扰你。若你本意就是要删除这个文件，请在之后重载 Hammerspoon：内存里没有任何策略时，缺失的文件就是一次首启，脚本会写入一份空的配置。

**通知提示某条策略已跳过**：一条交给 `networksetup` 会出问题的策略会在任何命令执行之前被拒绝，网卡就保持系统当前给它的配置。被拒绝的情形包括：`mode` 既不是 `dhcp` 也不是 `manual`、手动策略没有网关（该参数按位置取参，此前会以字面量 `nil` 被下发）、地址格式不正确、以及 `v6mode` 不在 `automatic` / `manual` / `off` 之内。日志会写明是哪个 SSID、哪个字段，请在编辑器或 `config.json` 里修正。

**切换之后 IPv6 不见了**：只有策略明确声明了 `v6mode`（`automatic`、`manual` 或 `off`）才会改动 IPv6。在该字段出现之前保存的策略、或手工编辑时删掉该字段的策略，都会保持 IPv6 现状不变。参数不齐的手动 IPv6 策略（缺地址、缺前缀长度或缺网关）会整组跳过而不是配置到一半，结果弹窗会写明这一点，而不是宣称成功。

**开机配置未生效**：模块在 Hammerspoon 加载时执行一次审计，此后每个 Wi-Fi 事件都会再执行；因此开机时还没连上路由器、之后才接入的网络会由 watcher 接手。若需要立刻重试，用菜单栏 → 强制重新检测网络。菜单栏 → 查看日志可以看到应用的规则以及任何失败的步骤。

**日志文件位置**：`~/.hammerspoon/wifi_autoconfig/wifi_autoconfig.log`（超过 7 天的条目会自动清理）

## 许可证

MIT