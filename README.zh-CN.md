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
- **菜单栏集成** — 快捷访问设置、日志、DHCP 重置与强制重新检测；双击图标可直接打开设置编辑器
- **VPN 路由概览** — 每条隧道或 VPN 按地址族分行列出它在路由表中安装了多少个网段（并给出其中几个），与网关、DNS 分开展示，因此分流型 VPN 和全局型 VPN 一眼就能区分
- **公网地址与代理出口地址** — 状态列表末尾给出公网看到的本机地址；启用 HTTP/HTTPS 代理时再补一行代理的出口地址，因此接口上的内网地址与流量实际显示的地址可以同时看到。后台每 2 分钟刷新一次，绝不占用打开菜单的那条路径
- **自绘状态面板** — 菜单栏状态视图改为自绘的无边框 WebKit 面板，使用固定的深色底色，因此琥珀色/绿色段标题在浅色与深色模式下都清晰可读，且信息行在悬停时不会高亮；清单比屏幕还高时面板会滚动，而不是把下面的行甩出屏幕（若 webview 创建失败会自动回退到原生菜单）
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
3. 把当前 SSID 与「上一次已经完整下发过规则的那个网络」比对：名字相同就在此停止，不下发任何命令，也不会再去读网卡来确认设置是否仍然生效。名字不同、或者根本没有记住的名字，才继续第 4 步；后一种正是 `Reload Config` 的情形，所以重新加载配置时一定会应用当前网络对应的规则并把结果弹窗告知。
4. 通过 `networksetup` 命令并使用 sudo 应用网络设置：
   - IPv4：`networksetup -setmanual` / `-setdhcp`
   - IPv6：`networksetup -setv6manual` / `-setv6automatic` / `-setv6off`
   - DNS：`networksetup -setdnsservers`（留空 = 恢复为 DHCP 自动 DNS）
5. 通过 `waitForCondition()` 轮询验证 IP/DNS 是否真正生效
6. 发送 macOS 通知并弹窗展示完整的网络报告，其中列出所有未完成的步骤（列表非空时标题改为「网络配置仅部分生效」）

读到「未连接」不会直接采信。`hs.wifi.currentNetwork()` 在任何一次 Wi-Fi 状态变化的瞬间都会返回 nil，而 watcher 对这些变化同样会触发；过去这样一次读数就会丢掉记住的 SSID，约一秒后到的那个事件报出的还是原本就在线的那个网络，于是它被当成新网络重新配置并弹一次窗。现在一次断开读数要经过 3 秒后的第二次读取确认才算数：换了个名字回来，就是名副其实的网络变化，照常应用；名字没变地回来了，说明链路根本就没断过，什么都不做；只有持续处于断开状态才会清掉记住的 SSID，所以同一个网络真正断线重连后仍然会重新下发——策略写进去的地址可能随关联一起丢了。

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
| 打开设置 | 打开 WebView 配置编辑器（`⌘S` 保存、`⌘W` 关闭） |
| 查看日志 | 在弹窗中显示最近的日志条目（可用鼠标选中并复制，也支持 `⌘A`、`⌘C`） |
| 将当前网络设为 DHCP | 立即将当前接口重置为 DHCP + 自动 DNS |
| 强制网络检测 | 清空已记住的 SSID 并立即重新执行网络审计，因此当前网络对应的规则会被重新下发一次并弹窗报告结果 |

**点击图标** — 单击打开状态面板，面板展开时再点一次图标将其关闭，**双击则直接打开设置编辑器**（面板随之收起）。双击是靠两次点击的时间间隔识别的，而不是系统的事件点击计数——因为 `hs.menubar` 的点击回调只报告修饰键；识别窗口为 0.4 秒。该行为只作用于自绘面板：原生菜单回退路径（仅在无法创建 WebKit 面板时使用）没有可供拦截的点击回调，因此在那里双击只是把菜单打开又关掉。

**菜单比屏幕高时** — 面板窗口的高度是按行模型算出来的，所以清单很长时窗口会比屏幕还高，超出底边的部分——正是那些能执行操作的动作行——就够不着了。现在窗口以「图标所在屏幕的可用高度」为上限（取该屏的 visibleFrame，因此止于 Dock 之上、并距屏幕边缘留一点余量），卡片内部滚动显示余下内容；窗口顶端始终贴在图标下方——以前把整块面板往上挪，正是超长菜单换成从顶部丢掉首批行的原因。滚动条被刻意画成零宽度：窗口的宽度是按卡片自身的盒子量出来的，占据布局宽度的滚动条会从行文本那里抢走这些像素，于是「底边那行被切掉」本身就是还有内容的提示。卡片能滚动之后，指针底下是哪一行就不再能由 Lua 按模型推算，所以 Lua 只把指针在窗口内的坐标交给渲染层，由 `elementFromPoint` 判定，并在每次滚动后重新判定。放得下的菜单一切照旧：高度正好等于所有行，也不生成滚动区。

### VPN 各行怎么读

每检测到一个隧道或 VPN，都会报告三件不同的事，而它们不能互相替代；通过客户端 API 认领下来的隧道还会多报一件 `模式`，就是下表最后一行：

| 行 | 它是什么 | 它决定什么 |
|----|----------|------------|
| `IPv4/gateway` / `IPv4`、`网关 (IPv6)` | 隧道通告的下跳地址，且只在它确实通告了一个时才写进行头。IPv4 的下跳可用时跟在地址后面，以 `>>` 表示，那一行的行头就是 `IPv4/gateway`（`IPv4/gateway: 10.0.0.2>>198.18.0.1`）；没有下跳可写时，那一行只保留地址，行头改回 `IPv4`——点对点隧道通常就属于这种：路由表里只有链路层网关（`link#N`）而没有点对点地址可以替换，或者下跳就是接口自身已经占用的那个地址（TUN 模式代理正是如此）。IPv6 的网关单独占一行，紧跟在它的 IPv6 地址下面，且只有该接口确实有 IPv6 地址时才显示。 | 交给这个网卡的报文交给哪个路由器 |
| `路由 (IPv4)`、`路由 (IPv6)` | 隧道为该地址族在路由表里安装了多少个网段，排在它们所路由的地址与网关之后，并列出其中至多三个示例以及本族总数（`路由 (IPv4): 10.0.0.0/8, 192.168.0.0/16 (共 137 条)`、`路由 (IPv6): fd7a:115c:a1e0::/48 (共 4 条)`）。某个地址族没有路由时就不显示它那一行，所以纯 IPv4 隧道不会被看成也在承载 IPv6。每个网段都写成完整的 CIDR，包括 `netstat` 缩写过的那些——它那行输出里光秃秃的一个 `1`，就是 `1.0.0.0/8`。 | **哪些目标地址根本就走这条隧道**——分流隧道（split tunnel）正是由这一项构成的 |
| `DNS` | 该接口配置的解析器 | 域名如何变成 IP；至于解析出的流量走哪条路，它什么都不说明 |
| `模式` | 客户端内核自己的分流模式，写在名字下面那一行（`模式: 规则`）。只有通过客户端 API 认领了接口的隧道带有这个字段：系统 VPN、`WireGuard` 隧道、代理行和认不出归属的接口都不会出现 `模式` 这一行。 | 隧道是逐条连接按自己的规则选路（`规则`）、把所有连接都从同一个出口送出（`全局`），还是全部直连（`直连`） |

因此接管一切的 VPN 会带上一条默认路由、`路由` 的总数很大，而分流隧道只列出它自己那几段地址——`路由` 这几行就是区分二者的依据，也能解释「VPN 明明连着，这个站点却还是从本机出口出去了」这类现象。地址旁标注的 `默认出口` 表示该接口当前持有系统的默认路由。

**左边的名字是从哪来的。** 名字后面方括号里的来源，说明这一行是哪一路查找给出的：`scutil --nc list` 里的服务记作 `macOS VPN`；`/var/run/wireguard/` 下有对应套接字的隧道记作 `WireGuard`；没有建立 TUN 设备的代理客户端记作 `Proxy`；其余谁也没认领的接口记作 `Tunnel`——只有这一种情况会显示成 `utun1024 [Tunnel]` 这样的接口名而不是程序名。确实建立了 TUN 设备的客户端，是通过它自己的本地 API 来对应的，因为这个 API 会报告它创建了哪个接口。而这个 API 并不总在 TCP 端口上：Clash Verge 的服务用 `-ext-ctl-unix <路径>` 启动内核，并把 `external-controller` 设为空，因此 9090、9097 上什么都没监听，只扫固定端口就会以为这台机器上一个代理都没有。所以现在改成从内核自己的启动参数里读端点（`-ext-ctl-unix`、`-ext-ctl`）并向它发问，同时保留 `9090`、`9097`、`7892`、`11227` 这份固定列表，供只配了 TCP 控制端口的内核使用。程序名取自拥有该端点的那个进程，因此尽管有几个客户端跑的是同一个 mihomo 内核，`Clash Verge`、`FlClash`、`Karing`、`sing-box`、`mihomo-party` 仍能被区分开。每次请求的时限约一秒；API 没有应答的隧道仍显示接口名——接口是真实存在的，认不出归属就按认不出归属来显示，而不是猜一个。方括号里只放这一种事实，内核的运行模式不再挤在里面，而是单独占一行：这个模块认得的词按界面语言翻译，认不出的就照内核给出的原样显示。由接口整理出来的那些行也有固定顺序：先按同一个来源类型分组——`TUN`、然后 `WireGuard`、然后是没人认领的接口——再按这一行显示的名字排，最后按接口编号排。编号是按数字比的，否则 `utun1025` 会按文本排在 `utun7` 前面；而没人认领的接口，名字就是接口本身，所以这一档跳过名字直接看编号。这样一个有两条隧道的客户端会并排出现，而不是被别的客户端的行列隔开，同一台机器在每次重载后列出的顺序也保持一致。

### 公网地址那几行怎么读

当前网络信息块的最后几行，说明这台机器在公网上以哪个地址出现：

| 行 | 它是什么 |
|----|----------|
| `公网 IP` | 对端看到的本机地址，取自 Wi-Fi 接口自己的通路 |
| `代理出口 IP` | 流量经过代理时实际显示的地址。只有在 Wi-Fi 服务上启用了 HTTP 或 HTTPS 代理时才显示，因为那是两个答案唯一会不同的场合 |

两行都排在 `DNS` 之后、当前网络块的末尾，它们提供的是上面那些行给不出的信息：接口地址是内网地址，而且隧道可以在不告明的情况下接管通路。若默认路由由 VPN 持有，`公网 IP` 显示的就是这条隧道的出口地址，而不是你路由器的地址。

关于这两行如何取到数据，有三点值得知道：

- **面板不会等待探测。** 这是唯一必须离开本机才能读到的状态，所以它走自己那条 2 分钟定时器，而不是 5 秒一次的本地刷新；网络变化后数秒也会再探测一次（若此刻正在下发配置，探测会等它写完——否则这次阻塞读取会占用校验配置是否生效的等待窗口）。第一次探测返回之前该行显示「检测中…」；没有任何端点应答时显示「获取失败」，菜单其余部分不受影响。
- **四个服务，先答者生效。** 地址来自一次 HTTPS 请求，依次尝试 `api.ipify.org`、`ip.3322.net`、`ifconfig.co`、`ip.sb`；只要其中一个回应，其余就不再访问。顺序在国内网络下是有意义的：几个知名回显服务可能被 TUN 模式代理解析成 fake-IP 段里的地址，于是在机器明明在线的情况下全部超时——而 `ip.3322.net` 在那里不到一秒就能应答。每次请求的时限约一秒，所以通路失效或被劫持只会让这一次刷新变慢，不会卡住菜单。若你不希望模块访问这些域名，在防火墙里拦掉即可——那两行只会显示「获取失败」。
- **只配置 PAC 的代理检测不到。** `代理出口 IP` 读的是服务上的代理设置（`networksetup -getwebproxy` / `-getsecurewebproxy`）；只指向 PAC 文件的设置在那里没有条目，因此只会显示直连地址。

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
- **辅助功能 / 输入监控权限** — 模块使用 `hs.eventtap` 监听状态面板之外的鼠标点击，点击面板外部即收起面板。请在**系统设置 → 隐私与安全性 → 辅助功能**或**输入监控**中授予访问权限，然后重新加载 Hammerspoon。键盘快捷键与此无关：编辑器的 `⌘S`（保存）、`⌘W`（关闭），以及日志窗口、结果弹窗里的选中与复制，全部由页面自身处理，不需要任何系统权限。
- `networksetup` 所需的 sudo 权限。安装器可为**当前账户单独**写入免密 sudoers 规则；没有该规则时网络变更不会提示输密码，而是直接失败（见常见问题）。

## 常见问题

**切换网络后什么都没变**：模块通过 `sudo /usr/sbin/networksetup` 修改网络设置，而 `io.popen` 不会给 sudo 分配终端，所以缺少 sudoers 规则时并不会弹出密码框——命令直接失败，结果弹窗会列出未完成的步骤。安装时安装器可在 `/etc/sudoers.d/hammerspoon_wificonfig` 为**当前账户单独**写入免密规则，刻意不放行给 `%admin`：任何本机进程都能以该管理员身份免密执行 `-setdnsservers`，这是一条比本模块活得更久的 DNS 劫持通道。规则只点名模块用到的子命令（`setmanual`、`setdhcp`、`setdnsservers`、`setv6manual`、`setv6automatic`、`setv6off`、`listallnetworkservices`），而不是放行整个二进制；卸载时 `scripts/uninstall.sh` 会删除它写下的文件。规则文件先写到临时路径，用 `visudo -cf` 校验通过之后才移入原位，因此一次失败的校验不会在 `/etc/sudoers.d` 留下破损的 drop-in；安装器随后还会用免密探测确认这条规则对你的账户确实生效，才报告成功。写入之前它会先征求你的同意；没有终端可供提问时（管道执行的 `curl | bash`）它拒绝写入这条规则，只打印你自己添加时要用到的命令——一份长期有效的授权不该因为没人应答就被创建。

若要自己添加，运行 `sudo visudo -f /etc/sudoers.d/hammerspoon_wificonfig`，把下面这行中的 `<your-user>` 换成你的账户名后加入，并用 `sudo visudo -cf /etc/sudoers.d/hammerspoon_wificonfig` 校验语法。请注意最后一项与其他项不同，它后面没有 `*`：sudoers 的 `*` 匹配的是参数，而不是「参数的缺失」，所以写成 `-listallnetworkservices *` 会让安装器用来探测的那个不带参数的调用被拒绝（3.2.1 装出的规则正是这个形态——切换网络照常工作，只有探测报称失败）。

```
<your-user> ALL=(root) NOPASSWD: /usr/sbin/networksetup -setmanual *, /usr/sbin/networksetup -setdhcp *, /usr/sbin/networksetup -setdnsservers *, /usr/sbin/networksetup -setv6manual *, /usr/sbin/networksetup -setv6automatic *, /usr/sbin/networksetup -setv6off *, /usr/sbin/networksetup -listallnetworkservices
```

早期版本可能把规则写在 `/etc/sudoers.d/hammerspoon_netconfig` 或 `/etc/sudoers.d/hammerspoon_network`，而 v3.1.0 放行的是整个二进制而非逐条子命令。安装器会查找任何提到 `networksetup` 的 drop-in，打印其完整内容，说明它是否比当前规则更宽（授予了 `%admin` 这类用户组，或没有指定子命令而就放行了整个二进制），并列出它缺少哪些必需子命令。sudo 把多条规则视为可选项的叠加，所以只要那条宽规则还在，无论新文件写得多窄都约束不住权限——因此安装器在新规则验证通过之后，会删除**它自己写下的**遗留文件（凭文件里的标记行识别）。不是它写的文件绝不会被删：内容会打印出来，并告诉你用 `visudo -f` 自行查看。正因为这条遗留规则无论如何都仍然有效，即使某个未标记的宽规则已经让免密探测通过，安装器依然会收窄它自己管理的那份（`hammerspoon_wificonfig`），并且只在确认新授权生效之后才动旧文件；如果你在存在过宽规则时拒绝了添加规则，脚本会明确说明本次没有写入任何东西、更宽的权限仍在生效。对于没有密码就读不到的 drop-in，脚本只报告「无法判断」而不是猜。

**弹窗提示 config.json 无法解析**：模块会停在这里等你处理。你的策略仍然完整保留在该文件里——它只是停止读取，并在重新可解析之前拒绝写入，所以一个漏掉的逗号不会让你丢掉整个文件。修正语法（用 JSON 校验工具，或 `plutil -lint`）后点**重新读取**，文件会立刻被重读，写入与自动切换随之恢复，不需要重载 Hammerspoon。点**稍后处理**则维持在这个安全状态，同样且未再变动的内容不会反复打扰你（文件又出现新的破损时会重新提示）。在此期间自动切换被跳过，而不是降级成 DHCP；从编辑器发起的保存/删除也会被拒绝并单独弹窗告知，内存里不会留下磁盘上并不存在的半份策略。

**弹窗提示 config.json 不见了**：与上一条是同一个安全状态，只是抵达方式不同——模块内存里还装载着策略，文件却被删除或被截成了 0 字节。把它当作「没有策略」意味着一张空的策略表，下一次切换就会因找不到该 SSID 的策略而把网卡强制设为 DHCP，静态网络当场失去地址。因此策略继续留在内存中，写入保持拒绝、自动切换跳过，直到你把文件放回来（从备份恢复，或用它旁边的 `config.json.backup`），之后点**重新读取**即可接管，无需重载 Hammerspoon。点**稍后处理**会保持该状态且不再反复打扰你。若你本意就是要删除这个文件，请在之后重载 Hammerspoon：内存里没有任何策略时，缺失的文件就是一次首启，脚本会写入一份空的配置。

**通知提示某条策略已跳过**：一条交给 `networksetup` 会出问题的策略会在任何命令执行之前被拒绝，网卡就保持系统当前给它的配置。被拒绝的情形包括：`mode` 既不是 `dhcp` 也不是 `manual`、手动策略没有网关（该参数按位置取参，此前会以字面量 `nil` 被下发）、地址格式不正确、以及 `v6mode` 不在 `automatic` / `manual` / `off` 之内。日志会写明是哪个 SSID、哪个字段，请在编辑器或 `config.json` 里修正。

**命令执行了却不见结果窗口**：报告窗口是在最后一条命令之后约一秒排定的，而「那条命令」与「那个窗口」之间曾有三处都能无声失败——日志因此可以停在命令那一行，对丢失的窗口只字不提。现在这三处各会留下一行。一次性定时器只靠 `hs.timer.doAfter` 交回的那个对象续命，所以没人持有的已排定报告可能在触发之前就被回收掉；现在每一次计划好的等待都会被留到执行完毕，之后再放手。系统通知并不是报告：当 macOS 不肯接收本应用的通知时（权限被关闭，或注册在某次重启后丢失），`hs.notify` 是直接抛出错误而不是返回一个值，而这个错误过去恰好落在「最后一条命令」与「窗口」之间，把后面的报告一起取消；现在被拒绝的通知只留下一行日志，写明「配置结果的报告窗口不受影响」，而且窗口是先排上定时器、再去发横幅。若 `ui/templates/popups.html` 读不到，日志会直说模板缺失，而不是悄悄返回——这正是「弹窗根本没被建出来」与「根本没人要弹窗」的区别。所以请打开菜单栏 → 查看日志，把命令行之后的内容读到底。如果这三行都没有出现，请告之静默之前的最后一行是什么。

**切换之后 IPv6 不见了**：只有策略明确声明了 `v6mode`（`automatic`、`manual` 或 `off`）才会改动 IPv6。在该字段出现之前保存的策略、或手工编辑时删掉该字段的策略，都会保持 IPv6 现状不变。参数不齐的手动 IPv6 策略（缺地址、缺前缀长度或缺网关）会整组跳过而不是配置到一半，结果弹窗会写明这一点，而不是宣称成功。

**开机配置未生效**：模块在 Hammerspoon 加载时执行一次审计，此后每个 Wi-Fi 事件都会再执行；因此开机时还没连上路由器、之后才接入的网络会由 watcher 接手。若需要立刻重试，用菜单栏 → 强制重新检测网络。菜单栏 → 查看日志可以看到应用的规则以及任何失败的步骤。

**日志文件位置**：`~/.hammerspoon/wifi_autoconfig/wifi_autoconfig.log`（超过 7 天的条目会自动清理）

## 许可证

MIT