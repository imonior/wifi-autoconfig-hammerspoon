# Wi-Fi AutoConfig for Hammerspoon v3.2.4

A Hammerspoon-based macOS Wi-Fi network auto-switching tool. This release ships a
**self-contained offline install bundle** — download the zip, extract, and run
`bash scripts/install.sh` with no network access to GitHub required.

基于 Hammerspoon 的 macOS Wi-Fi 网络自动切换工具。本版本提供**自包含离线安装包**：
下载 zip、解压后运行 `bash scripts/install.sh` 即可，无需访问 GitHub。

## What's in the bundle / 发布包内容

- `src/` — all Lua modules (init / core / config / utils / i18n / menu_builder / network_apply / panel / ui)
- `scripts/` — install.sh · uninstall.sh · legacy-install.sh · legacy-uninstall.sh
- `config.example.json`, `LICENSE`, `README.md` / `README.zh-CN.md`, `CHANGELOG.md` / `CHANGELOG.zh-CN.md`

## Offline install / 离线安装

```bash
unzip wifi-autoconfig-hammerspoon-v3.2.4.zip
cd wifi-autoconfig-hammerspoon
bash scripts/install.sh
```

## Upgrading from a previous (pre-3.0) version / 旧版本升级

```bash
bash scripts/legacy-install.sh --force
```

See CHANGELOG.md (English) / CHANGELOG.zh-CN.md (简体中文) for the full history.
