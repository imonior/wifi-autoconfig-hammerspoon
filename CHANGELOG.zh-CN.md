# 更新日志

[English](CHANGELOG.md) | [简体中文](CHANGELOG.zh-CN.md)

**Wi-Fi AutoConfig for Hammerspoon** 的所有重要变更都记录在此文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [3.0.0] - 2026-09-29

### 新增

- **离线发布包** —— `scripts/build-release.sh` 将 `src/`、`scripts/` 与全部文档打包为单个
  `wifi-autoconfig-hammerspoon-vX.Y.Z.zip`，支持完全离线安装。
- **独立发布页** —— 由构建脚本生成的 `release.html`（深色主题）与 `RELEASE.md` 发布说明。
- **本地 / 离线安装模式** —— `install.sh` 现可识别是否运行于解压后的归档目录内，
  直接使用打包文件安装，不再从 GitHub 下载。
- **旧版本升级 / 卸载脚本** —— `legacy-install.sh`（清理 3.0 之前版本后一步安装 v3.0.0）
  与 `legacy-uninstall.sh`（仅卸载 3.0 之前版本）。

### 变更

- **统一备份位置** —— 配置备份改为写入 `~/.wifi_autoconfig_backups/`
  （可用 `BACKUP_DIR` 环境变量覆盖），不再依赖桌面目录，同时修复了无 `~/Desktop` 时安装失败的问题。
- 模块版本号提升至 `3.0.0`（安装器、卸载器、`init.lua`、`i18n.lua`）。

## [1.0.0] - 2026-09-28

首个正式发布版本。安装路径为 `~/.hammerspoon/wifi_autoconfig/`，
通过 `require("wifi_autoconfig.init")` 加载。

### 新增

- **基于 SSID 的自动切换** — `hs.wifi.watcher` 监听 Wi-Fi 变化并应用匹配的配置。
- **每个 SSID 独立配置** — 每个网络可单独设置静态 IP / DHCP / 自定义 DNS / IPv6（`automatic`、`manual`、`off`）。
- **全局兜底策略** — `__DEFAULT__` 配置覆盖所有未单独配置的 SSID。
- **WebView 编辑器** — 内置 HTML/CSS 面板管理配置，并实时同步硬件状态。
- **强制覆写** — 将编辑器内容直接应用到网卡，弹窗确认展示完整配置详情。
- **菜单栏集成** — 设置、日志、DHCP 重置、强制重新检测，并实时显示 Wi-Fi / IPv4 / IPv6 / DNS / VPN 状态。
- **中英双语界面** — 通过 `hs.host.locale` 自动检测，模块、编辑器与安装脚本均跟随系统语言。
- **7 天日志轮转** — 写入时自动清理 `wifi_autoconfig.log` 中超期条目。
- **配置校验** — 保存前校验 IPv4 / 子网掩码 / 网关 / DNS 格式。
- **安装与卸载脚本** — `install.sh`（全新安装 / `--update` / `--force` / `--proxy`）与 `uninstall.sh`。

### 变更

- 日志文件更名为 `wifi_autoconfig.log`。
- 菜单栏重建复用 5 秒状态缓存，连续点击不再重复 fork 二十多个 shell 探测进程。
- 暗色模式检测（`defaults read`）结果缓存 5 秒。

### 移除

- 全部 1.0 之前的兼容层：`wifi_ip_config.json` / `wifi_ip_switcher.log` 的迁移逻辑已删除。
  安装脚本会直接删除 1.0 之前的旧目录，并从 `init.lua` 移除对应的 `require` 行，不做数据迁移。
