[English](README.md) | [简体中文](README.zh-CN.md)

# Wi-Fi AutoConfig for Hammerspoon

> A high-performance, fully async macOS network auto-switcher built on Hammerspoon.

Automatically switches network configurations (static IP / DHCP / custom DNS / IPv6) based on the connected Wi-Fi SSID. Detects SSID changes in real time and applies the matching profile within seconds.

## Features

- **Automatic SSID-based switching** — `hs.wifi.watcher` monitors SSID changes and applies the matching network profile instantly
- **Per-SSID network profiles** — Each Wi-Fi network can have its own static IP, subnet, gateway, DNS, and IPv6 settings
- **Static IP & DHCP modes** — `"manual"` for static binding, `"dhcp"` for dynamic allocation with optional custom DNS
- **IPv6 control** — `automatic`, `manual`, or `off` per network
- **Global fallback policy** — The `__DEFAULT__` profile applies to any unconfigured SSID
- **Force-apply from editor** — Apply editor contents directly to the network interface without saving, with a confirmation dialog showing full config details
- **WebView configuration editor** — Built-in HTML/CSS UI for managing network profiles with live hardware status sync
- **Menu bar integration** — Quick access to settings, logs, DHCP reset, and force re-detection
- **Self-drawn status panel** — the menu-bar status view is a custom borderless WebKit panel with a fixed dark surface, so the amber/green section colours stay readable in both light and dark mode and informational rows never highlight on hover (falls back to the native menu automatically)
- **Bilingual (zh/en)** — Auto-detects system language via `hs.host.locale`
- **7-day log rotation** — Automatic cleanup of log entries older than 7 days
- **Startup auto-apply** — On Hammerspoon load, applies the current SSID's config with retry logic (5 attempts, 1s interval) for Wi-Fi readiness
- **Config validation** — IP/netmask/gateway/DNS format validation on save, prevents broken network settings

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash
```

### China Mirror

If direct GitHub access is slow in mainland China, use a proxy mirror:

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash
```

To update via the mirror, add the proxy prefix as well:

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash -s -- --update
```

You can also specify any proxy via an environment variable or the `--proxy` flag:

```bash
# Environment variable
GITHUB_PROXY=https://ghfast.top/ bash install.sh

# Command-line flag
bash install.sh --proxy https://ghfast.top/
```

This will:
1. Install Hammerspoon (via Homebrew or direct download) if not present
2. Download the project tarball and install to `~/.hammerspoon/wifi_autoconfig/`
3. Inject `require("wifi_autoconfig.init")` into `~/.hammerspoon/init.lua` (idempotent)
4. Reload Hammerspoon
5. Optionally set up passwordless sudo for `/usr/sbin/networksetup` so network switches never prompt for a password

## Update

```bash
curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash -s -- --update
```

Or locally:

```bash
bash scripts/install.sh --update
```

Updates preserve your `config.json` (backed up to `config.json.backup` during update).

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/uninstall.sh | bash
```

Via the China mirror:

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/uninstall.sh | bash
```

Or locally:

```bash
bash scripts/uninstall.sh              # Interactive (prompts for config backup)
bash scripts/uninstall.sh --force      # Skip prompts, auto-backup config to ~/.wifi_autoconfig_backups/
```

The uninstaller backs up your `config.json` to `~/.wifi_autoconfig_backups/wifi_autoconfig_config_backup.json` before removing the module. Override the location with the `BACKUP_DIR` environment variable. Hammerspoon itself is not removed.

## Migrating from a previous version

This project was previously released under an older name (installed as
`~/.hammerspoon/wifi_ip_switcher` or `~/.hammerspoon/wifi_ip_controller`).
v3.0.0 is a clean restart, so the installer does **not** migrate old data
automatically.

If you have an older release installed, run the dedicated legacy upgrade script.
It backs up each old `config.json` to `~/.wifi_autoconfig_backups/` (one file per old directory),
removes the old module + its `init.lua` reference, then launches the v3.0.0
installer in one step:

```bash
bash scripts/legacy-install.sh            # Interactive (prompts before cleanup)
bash scripts/legacy-install.sh --force    # Skip the cleanup prompt
```

If you do **not** want v3.0.0 and only wish to remove the old release completely,
use:

```bash
bash scripts/legacy-uninstall.sh            # Interactive
bash scripts/legacy-uninstall.sh --force    # Skip prompts
```

## Offline install (release package)

Every release publishes a self-contained archive, `wifi-autoconfig-hammerspoon-vX.Y.Z.zip`,
that bundles all scripts and source files. It can be installed on a machine that has no
access to GitHub:

1. Download `wifi-autoconfig-hammerspoon-vX.Y.Z.zip` from the release page.
2. Unzip it:
   ```bash
   unzip wifi-autoconfig-hammerspoon-vX.Y.Z.zip
   cd wifi-autoconfig-hammerspoon
   ```
3. Run the installer from inside the extracted folder. It detects the bundled
   files and installs them locally — no network needed:
   ```bash
   bash scripts/install.sh
   ```

To build the archive yourself (needs only `zip`/`tar`, no network):

```bash
bash scripts/build-release.sh
# produces dist/wifi-autoconfig-hammerspoon-vX.Y.Z.zip and release.html
```

## Manual Install

1. Install [Hammerspoon](https://hammerspoon.org)
2. Copy project files to `~/.hammerspoon/wifi_autoconfig/`:
   ```bash
   mkdir -p ~/.hammerspoon/wifi_autoconfig/ui/templates ~/.hammerspoon/wifi_autoconfig/ui/icons
   cp src/*.lua ~/.hammerspoon/wifi_autoconfig/
   cp src/ui/*.lua ~/.hammerspoon/wifi_autoconfig/ui/
   cp src/ui/templates/*.html ~/.hammerspoon/wifi_autoconfig/ui/templates/
   cp src/ui/icons/*.svg ~/.hammerspoon/wifi_autoconfig/ui/icons/
   cp config.example.json ~/.hammerspoon/wifi_autoconfig/config.json
   ```
3. Add to `~/.hammerspoon/init.lua`:
   ```lua
   -- ~/.hammerspoon/init.lua
   require("wifi_autoconfig.init")
   ```
4. Reload Hammerspoon (menu bar icon → Reload Config, or `hs.reload()` in console)

### Auto-open editor on startup

By default, the module runs silently in the background. To auto-open the configuration editor when Hammerspoon loads, add this at the end of `M.init()` in [init.lua](init.lua):

```lua
hs.timer.doAfter(2, function()
    config.read()
    ui.showEditor(config.current)
end)
```

## How It Works

### Auto-switching flow

1. `hs.wifi.watcher` detects SSID change → triggers `performNetworkAudit()`
2. Looks up config for the new SSID (falls back to `__DEFAULT__`, then raw DHCP)
3. Applies network settings via `networksetup` commands with sudo:
   - `networksetup -setmanual` / `-setdhcp` for IPv4
   - `networksetup -setv6manual` / `-setv6automatic` / `-setv6off` for IPv6
   - `networksetup -setdnsservers` for DNS (empty = clear to DHCP)
4. Polls via `waitForCondition()` to verify IP/DNS actually took effect
5. Sends a macOS notification and shows a popup with the full network report

### Config source types

| Source | When |
|--------|------|
| Custom Policy | SSID has a dedicated profile in `config.json` |
| Global Fallback | SSID not configured, `__DEFAULT__` applies |
| DHCP Auto | No config at all, falls back to system DHCP |
| Editor Temp Config | Force-apply from editor without saving |

### Menu bar functions

| Menu item | Action |
|-----------|--------|
| Open Settings | Opens the WebView configuration editor |
| View Logs | Shows recent log entries in a popup |
| Set Current Network to DHCP | Immediately resets current interface to DHCP + auto DNS |
| Force Network Detection | Closes editor, clears SSID cache, re-runs network audit |

## Configuration

Edit `~/.hammerspoon/wifi_autoconfig/config.json`, or use the built-in editor (menu bar icon → Open Settings).

### Config fields

| Field | Description |
|-------|-------------|
| `mode` | `"dhcp"` or `"manual"` |
| `ip` | IPv4 address (manual mode) |
| `netmask` | Subnet mask (default: `255.255.255.0`) |
| `gateway` | Router IP (manual mode) |
| `dns` | DNS servers, comma-separated. Empty = DHCP auto |
| `v6mode` | `"automatic"`, `"manual"`, or `"off"` |
| `ipv6` | IPv6 address (manual mode) |
| `v6prefix` | IPv6 prefix length (default: `64`) |
| `v6gateway` | IPv6 router (manual mode) |

### Example

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

## Project Structure

The module follows a **presentation-core separation** architecture — the presentation layer and core logic are fully decoupled for performance and maintainability:

```
wifi-autoconfig-hammerspoon/
├── CHANGELOG.md              # Release history (en)
├── CHANGELOG.zh-CN.md        # Release history (zh)
├── scripts/                  # Installer scripts
│   ├── install.sh            # One-command installer (--update / --force / --help)
│   ├── uninstall.sh          # Uninstaller (--force)
│   ├── legacy-install.sh    # One-step upgrade: clean a pre-1.0 install then install v3.0.0
│   └── legacy-uninstall.sh   # One-time full removal of a pre-1.0 install
├── config.example.json       # Example config template
├── src/                      # Source code directory
│   ├── init.lua              # Entry: menu bar, Wi-Fi watcher, auto-switch, startup audit
│   ├── core.lua              # Core: sudo networksetup, Wi-Fi status, RSSI, DNS, IPv6
│   ├── config.lua            # Data: config persistence + hs.urlevent handlers + validation
│   ├── utils.lua             # Utils: logging (7-day rotation), async wait/poll, HTML escape
│   ├── i18n.lua              # i18n: zh/en translations, auto-detect via hs.host.locale
│   ├── menu_builder.lua      # Menu Builder: menubar construction + dark mode detection
│   ├── network_apply.lua     # Network Apply: network configuration application logic
│   └── ui/                   # Presentation
│       ├── web_view.lua      #   WebView controller: window lifecycle, editor + popup management
│       └── templates/        #   Pure frontend templates
│           ├── editor.html   #     Configuration editor panel (full UI/interaction/CSS)
│           └── popups.html   #     Multi-modal popup (reused for log viewer + success notifications)
```

### Layer responsibilities

- **Presentation layer** (`ui/`): WebView windows and HTML templates. The editor injects config JSON and network list into HTML at runtime, communicates back via `hs.urlevent` URL schemes (`hammerspoon://save_wifi_scene`, `hammerspoon://force_apply_network`, etc.).
- **Core logic** (`core.lua`): All network operations via `networksetup` with sudo, with `shellQuote()` for safe argument escaping. Wi-Fi status detection uses `hs.wifi.currentNetwork()` for SSID, `hs.wifi.interfaceDetails()` for RSSI (with `system_profiler SPAirPortDataType` as fallback).
- **Data layer** (`config.lua`): JSON-based config with IPv4/DNS format validation on save. Stored at `~/.hammerspoon/wifi_autoconfig/config.json`.
- **Utilities** (`utils.lua`): Async helpers — `waitForCondition()` polls with configurable timeout/interval, `executeWithRetry()` for retry logic. Log file auto-rotates entries older than 7 days.

All network operations are **fully async** using `hs.timer.doAfter` — no blocking calls.

## Requirements

- macOS 13+ (tested on macOS 15 Sequoia)
- Hammerspoon 0.4.3+
- Sudo access (for `networksetup` commands — the installer can set up passwordless sudo, otherwise Hammerspoon prompts on first use)
- Location Services access (optional, for Wi-Fi RSSI signal strength display)

## Troubleshooting

**Sudo prompts**: The module uses `sudo /usr/sbin/networksetup` to change network settings. During install, the installer can optionally write a passwordless sudoers rule to `/etc/sudoers.d/hammerspoon_wificonfig`, so network switches run silently without prompting. The rule is scoped to the subcommands the module actually uses (`setmanual`, `setdhcp`, `setdnsservers`, `setv6manual`, `setv6automatic`, `setv6off`, `listallnetworkservices`) rather than granting the whole binary. If you skipped that step (or on a machine without the rule), configure it manually: run `sudo visudo -f /etc/sudoers.d/hammerspoon_wificonfig` and add `<your-user> ALL=(root) NOPASSWD: /usr/sbin/networksetup -setmanual *, /usr/sbin/networksetup -setdhcp *, /usr/sbin/networksetup -setdnsservers *, /usr/sbin/networksetup -setv6manual *, /usr/sbin/networksetup -setv6automatic *, /usr/sbin/networksetup -setv6off *, /usr/sbin/networksetup -listallnetworkservices *` (validate with `visudo -cf <file>` before saving).

**RSSI shows as Unknown**: macOS 15+ requires Location Services access for Wi-Fi signal info. Go to System Settings → Privacy & Security → Location Services → enable Hammerspoon. If unavailable, the signal line is hidden from popups.

**Config not applying on startup**: The module retries 5 times (1s interval) waiting for Wi-Fi to connect after Hammerspoon loads. Check logs via menu bar → View Logs for `runInitialAudit` entries.

**Log file location**: `~/.hammerspoon/wifi_autoconfig/wifi_autoconfig.log` (entries older than 7 days are pruned automatically)

## License

MIT