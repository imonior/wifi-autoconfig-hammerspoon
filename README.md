[English](README.md) | [简体中文](README.zh-CN.md)

# Wi-Fi AutoConfig for Hammerspoon

> A macOS network auto-switcher built on Hammerspoon, with timer-driven waits instead of blocking sleeps.

Automatically switches network configurations (static IP / DHCP / custom DNS / IPv6) based on the connected Wi-Fi SSID. Detects SSID changes in real time and applies the matching profile within seconds.

## Features

- **Automatic SSID-based switching** — `hs.wifi.watcher` monitors SSID changes and applies the matching network profile instantly
- **Per-SSID network profiles** — Each Wi-Fi network can have its own static IP, subnet, gateway, DNS, and IPv6 settings
- **Static IP & DHCP modes** — `"manual"` for static binding, `"dhcp"` for dynamic allocation with optional custom DNS
- **IPv6 control** — `automatic`, `manual`, or `off` per network
- **Global fallback policy** — The `__DEFAULT__` profile applies to any unconfigured SSID
- **Force-apply from editor** — Apply editor contents directly to the network interface without saving, with a confirmation dialog showing full config details
- **WebView configuration editor** — Built-in HTML/CSS UI for managing network profiles with live hardware status sync
- **Menu bar integration** — Quick access to settings, logs, DHCP reset, and force re-detection; double-clicking the icon opens the settings editor
- **VPN route summary** — each tunnel or VPN lists, in one row per address family, how many networks it has installed in the routing table (and a few of them), separate from its gateway and DNS, so a split-tunnel VPN is visibly different from a full-tunnel one
- **Self-drawn status panel** — the menu-bar status view is a custom borderless WebKit panel with a fixed dark surface, so the amber/green section colours stay readable in both light and dark mode and informational rows never highlight on hover (falls back to the native menu automatically)
- **Honest results** — The status of every `networksetup` call is collected; if a step fails (no passwordless sudo rule, for instance) the popup lists what did not complete instead of reporting success
- **Bilingual (zh/en)** — Auto-detects system language via `hs.host.locale`
- **7-day log rotation** — Automatic cleanup of log entries older than 7 days
- **Startup audit** — Applies the current SSID's config when Hammerspoon loads, then on every Wi-Fi event
- **Config validation** — IPv4, IPv6, subnet, gateway and DNS format validation before anything is saved or applied, so a typo cannot push a broken address onto the interface

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
5. Optionally set up passwordless sudo for `/usr/sbin/networksetup` so network switches run silently — without it the changes fail rather than prompting, and the popup lists which steps did not complete

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

It also cleans up what the installer left outside the module directory. The passwordless sudoers drop-in is removed only if it carries the marker line the installer writes, so a file you edited yourself - or that another tool created - is printed instead of deleted, and the same rule applies to the older drop-in names. The `require` line in `~/.hammerspoon/init.lua` is removed with the file backed up first, and a reference the uninstaller does not recognise is reported rather than rewritten. Questions go to `/dev/tty`, so a `curl | bash` run cannot have the rest of its own script body read as the answer. With no terminal attached the uninstaller keeps the safe defaults (your `config.json` is still backed up) and then stops with an explanation rather than answering the confirmation on your behalf.

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

The version comes from `MODULE_VERSION` in `scripts/install.sh`, and the script refuses to
build unless a git tag matches it: a package named v3.2.1 that is not tagged v3.2.1 (or was
tagged from a different commit) is exactly how a release page ends up pointing at the wrong
bytes. It warns when the matching tag is not on the current commit, and at the end it notes
whether the generated `release.html` / `RELEASE.md` differ from the committed copies.

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
2. Looks up config for the new SSID (falls back to `__DEFAULT__`, then raw DHCP; if `config.json` cannot be parsed the switch is skipped instead)
3. Applies network settings via `networksetup` commands with sudo:
   - `networksetup -setmanual` / `-setdhcp` for IPv4
   - `networksetup -setv6manual` / `-setv6automatic` / `-setv6off` for IPv6
   - `networksetup -setdnsservers` for DNS (empty = clear to DHCP)
4. Polls via `waitForCondition()` to verify IP/DNS actually took effect
5. Sends a macOS notification and shows a popup with the full network report, listing every step that did not complete (the title changes to "partially applied" when the list is not empty)

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
| Force Network Detection | Clears the remembered SSID and re-runs the network audit immediately |

**Clicking the icon** — one click opens the status panel, a second click on the icon while it is open closes it, and a **double-click opens the settings editor** directly (the panel comes down with it). The double-click is recognised from the gap between the two clicks rather than from a system click count, because `hs.menubar`'s click callback reports only the modifier keys; the window is 0.4s. It applies to the self-drawn panel - the native-menu fallback path (used only when the WebKit panel cannot be created) has no click callback to intercept, so there a double-click just opens and closes the menu.

### Reading the VPN rows

Each detected tunnel or VPN reports three different things, and they are not interchangeable:

| Row | What it is | What it decides |
|-----|------------|-----------------|
| `IPv4/gateway`, `Gateway (IPv6)` | The next hop the tunnel advertises. The IPv4 one rides the address line after `>>` (`IPv4/gateway: 10.0.0.2>>198.18.0.1`); the IPv6 gateway gets its own row, and only when the interface has an IPv6 address. A tunnel whose route table offers nothing but a link-layer gateway (`link#N`) is shown with its point-to-point peer address instead. | Which router the packets handed to that interface go to |
| `Route (IPv4)`, `Route (IPv6)` | How many networks the tunnel has installed for that address family, with up to three of them and the family's own total (`Route (IPv4): 10.0.0.0/8, 192.168.0.0/16 (137 total)`). A family with no route of its own shows no row, so an IPv4-only tunnel never looks like it carries IPv6 traffic. | **Which destinations go through the tunnel at all** — this is what split tunnelling is made of |
| `DNS` | The resolver the interface is configured with | How a name becomes an address; it says nothing about which path the traffic then takes |

So a VPN that takes over everything has a default route and a very large `Route` count, while a split-tunnel VPN shows only its own address ranges — the `Route` rows are what tell those two apart, and it is also what explains a "the VPN is connected but this site still goes out the WAN" case. The `Default egress` marker next to an address means that interface currently holds the system default route.

## Configuration

Edit `~/.hammerspoon/wifi_autoconfig/config.json`, or use the built-in editor (menu bar icon → Open Settings).

### Config fields

| Field | Description |
|-------|-------------|
| `mode` | `"dhcp"` or `"manual"`, checked on save and again before anything is applied. A stored entry from an older version that has no `mode` field is read as `dhcp` |
| `ip` | IPv4 address (manual mode) |
| `netmask` | Subnet mask (default: `255.255.255.0`) |
| `gateway` | Router IP. Required in manual mode: `-setmanual` takes it as a positional argument, so an omitted value used to be sent as the literal text `nil` |
| `dns` | DNS servers, comma-separated (a JSON array is accepted and stored back as a comma-separated string). Empty = DHCP auto |
| `v6mode` | `"automatic"`, `"manual"`, or `"off"`. Omitted or empty = IPv6 left as it is; only `"off"` disables it. Any other value is refused before a command runs |
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
│   ├── legacy-install.sh    # One-step upgrade: clean a pre-1.0 install, then install the current version
│   └── legacy-uninstall.sh   # One-time full removal of a pre-1.0 install
├── config.example.json       # Example config template
├── src/                      # Source code directory
│   ├── init.lua              # Entry: menu bar, Wi-Fi watcher, auto-switch, startup audit
│   ├── core.lua              # Core: sudo networksetup, Wi-Fi status, IPv4/IPv6, DNS, VPN
│   ├── config.lua            # Data: config persistence + hs.urlevent handlers + validation
│   ├── utils.lua             # Utils: logging (7-day rotation), async wait/poll, HTML escape
│   ├── i18n.lua              # i18n: zh/en translations, auto-detect via hs.host.locale
│   ├── menu_builder.lua      # Menu rows for both surfaces + dark mode detection
│   ├── panel.lua             # Status panel: borderless WKWebView replacement for the NSMenu
│   ├── network_apply.lua     # Network Apply: network configuration application logic
│   └── ui/                   # Presentation
│       ├── web_view.lua      #   WebView controller: window lifecycle, editor + popup management
│       └── templates/        #   Pure frontend templates
│           ├── editor.html   #     Configuration editor panel (full UI/interaction/CSS)
│           └── popups.html   #     Multi-modal popup (reused for log viewer + success notifications)
```

### Layer responsibilities

- **Presentation layer** (`ui/`, `panel.lua`): WebView windows and HTML templates. The editor injects config JSON and the network list into the HTML at runtime and communicates back through `hs.urlevent` URL schemes (`hammerspoon://save_wifi_scene`, `hammerspoon://force_apply_network_with_confirm`, etc.). `panel.lua` draws the menu-bar status list itself.
- **Core logic** (`core.lua`): All network operations via `networksetup` with sudo, with `shellQuote()` for safe argument escaping. The SSID comes from `hs.wifi.currentNetwork()`, falling back to `networksetup -getairportnetwork`; `networksetup -getinfo` is parsed once per read and shared by the IPv4 and IPv6 views.
- **Data layer** (`config.lua`): JSON-based config with IPv4/IPv6/subnet/gateway/DNS/mode format validation on save, checked again before a stored policy is applied, stored at `~/.hammerspoon/wifi_autoconfig/config.json`. If that file stops parsing (a hand-edit typo, for example), the module keeps working from the last good table in memory, leaves the file untouched on disk, and refuses every write until it parses again - so a failed read can never replace your policies. A modal dialog blocks until you either repair the file (**Retry** re-reads it in place, no reload needed) or say you will handle it later. The same protection covers a file that disappears or is truncated to zero bytes while policies are loaded: those are treated as a loss to recover from, not as "no policies".
- **Utilities** (`utils.lua`): Timer-based helpers — `waitForCondition()` polls with a configurable timeout and interval, `wait()` defers a callback, `blockAlertOnce()` shows a dialog only if no other dialog is waiting for an answer. Log file auto-rotates entries older than 7 days.

Network changes are driven by timers: the apply sequence waits on `hs.timer` polls (`waitForCondition`) instead of sleeping, so a switch does not freeze Hammerspoon. Two calls are deliberately blocking: `hs.dialog.blockAlert` for the force-apply confirmation and for the unreadable-config dialogs, and every `io.popen` command itself (a wedged `networksetup` would stall the timer callback that issued it - see the note in `core.lua`). Because a blocking dialog runs a nested modal loop, all of them go through one guard: a dialog requested while another is still open is skipped and logged rather than stacked on top. An apply sequence that is still waiting when you switch networks again is dropped rather than resumed: each sequence carries a token, and a superseded one stops writing DNS or IPv6 onto an interface that has already moved on to another network.

## Requirements

- macOS 13+ (tested on macOS 15 Sequoia)
- Hammerspoon 0.4.3+
- **Accessibility / Input Monitoring permission** — The module uses `hs.eventtap` to detect when the WebView configuration editor is focused, so that keyboard shortcuts (⌘S to save, ⌘W to close) work reliably. Without this permission, the editor will still open but those shortcuts won't respond. Grant access in **System Settings → Privacy & Security → Accessibility** or **Input Monitoring**, then reload Hammerspoon.
- Sudo access for `networksetup`. The installer can write a passwordless sudoers rule for **your account only**; without it, network changes fail instead of prompting (see Troubleshooting).

## Troubleshooting

**Nothing changes when the network switches**: The module runs `sudo /usr/sbin/networksetup`, and `io.popen` gives sudo no terminal, so a missing sudoers rule does not produce a password prompt - the command simply fails and the result popup lists the steps that did not complete. During install the installer can write a passwordless rule to `/etc/sudoers.d/hammerspoon_wificonfig` for **your account only**. It is deliberately not granted to `%admin`: a passwordless `-setdnsservers` reachable by every admin on the machine is a DNS-hijack primitive that outlives this module. The rule names only the subcommands the module uses (`setmanual`, `setdhcp`, `setdnsservers`, `setv6manual`, `setv6automatic`, `setv6off`, `listallnetworkservices`) instead of the whole binary, and `scripts/uninstall.sh` removes the file when you uninstall. The file is staged to a temporary path, checked with `visudo -cf` and only then moved into place, so a failed check cannot leave a broken drop-in behind; the installer then verifies the rule actually works for your account before reporting success. It asks before writing, and when there is no terminal to ask on (a piped `curl | bash`) it declines to write the rule and prints the command to add it yourself - a standing grant should not appear because nobody was there to answer.

To add it yourself, run `sudo visudo -f /etc/sudoers.d/hammerspoon_wificonfig`, add the line below with `<your-user>` replaced by your account name, and validate with `sudo visudo -cf /etc/sudoers.d/hammerspoon_wificonfig`. Note that the last subcommand carries no trailing `*`, unlike the others: sudoers matches `*` against arguments, not against their absence, so `-listallnetworkservices *` would refuse the argument-less call this installer probes with (and a rule copied from a 3.2.1 install has exactly that shape - switching still works, only the probe reports failure).

```
<your-user> ALL=(root) NOPASSWD: /usr/sbin/networksetup -setmanual *, /usr/sbin/networksetup -setdhcp *, /usr/sbin/networksetup -setdnsservers *, /usr/sbin/networksetup -setv6manual *, /usr/sbin/networksetup -setv6automatic *, /usr/sbin/networksetup -setv6off *, /usr/sbin/networksetup -listallnetworkservices
```

Earlier installs may have written this rule to `/etc/sudoers.d/hammerspoon_netconfig` or `/etc/sudoers.d/hammerspoon_network`, and v3.1.0 granted the whole binary rather than the individual subcommands. The installer looks for any drop-in that mentions `networksetup`, prints its contents, and says whether it is wider than the current rule (granted to a group such as `%admin`, or granting the bare binary with no subcommand) and which required subcommands it leaves out. Sudo treats separate rules as alternatives, so a wide leftover keeps working no matter how narrow the new file is - which is why the installer, once the new rule has verified, deletes the leftovers **it wrote** (recognised by the marker line in the file). A file it did not write is never touched: its contents are printed and you are told how to review it with `visudo -f`. Because that leftover stays in force either way, the installer narrows the rule it manages (`hammerspoon_wificonfig`) even when an unmarked wide file already makes the passwordless probe pass, and it warns that it only did so after the new grant was confirmed; if you decline the rule while an over-wide file exists, it says plainly that nothing was written and the broader permission is still granted. A drop-in it cannot read without a password is reported as unknown rather than guessed at.

**A dialog says config.json cannot be parsed**: The module stops there and waits for you. Your policies are still in that file - it only stopped reading it, and it refuses to write until it parses again, so a stray comma cannot cost you the whole file. Fix the syntax (a JSON linter, or `plutil -lint`) and press **Retry**: the file is re-read and writing plus automatic switching resume immediately, without reloading Hammerspoon. Pressing **Handle it later** keeps everything in the safe state, and the same unchanged bytes will not interrupt you again (a new break will). While the file is unreadable, automatic switching is skipped rather than falling back to DHCP, and a save or delete you attempt from the editor is refused with its own dialog - the policy is not left half-applied in memory.

**A dialog says config.json has gone missing**: The same safety state, reached differently - the file was deleted or truncated to zero bytes while the module still held policies in memory. Accepting that would mean an empty policy table, and the next switch would then find no policy for the SSID and force the interface onto DHCP, costing a static network its address. So the policies are kept, writing stays refused and switching is skipped until you bring the file back (restore it from a backup, or from `config.json.backup` next to it), after which **Retry** picks it up with no reload. **Handle it later** keeps that state without interrupting you again. If you meant to delete the file, reload Hammerspoon afterwards: with nothing loaded in memory an absent file is a first run, and an empty one is written.

**A notification says a policy was skipped**: A stored policy that would be dangerous to hand to `networksetup` is refused before any command runs, and the interface simply keeps what the system gave it. That covers a `mode` that is neither `dhcp` nor `manual`, a manual policy with no gateway (the argument is positional, so it used to travel as the literal text `nil`), a malformed address, and a `v6mode` outside `automatic` / `manual` / `off`. The log names the SSID and the field; fix it in the editor or in `config.json`.

**IPv6 is missing after a switch**: A policy changes IPv6 only when it declares `v6mode` (`automatic`, `manual` or `off`). Policies written before that field existed, or hand-edited without it, leave the current IPv6 configuration untouched. A manual IPv6 policy that is missing its address, prefix or router is skipped as a set rather than applied half-way, and the result popup says so instead of reporting success.

**Config not applying on startup**: The audit runs once while Hammerspoon loads and then on every Wi-Fi event, so a network that joins later is picked up by the watcher. If the machine is still associating with the access point when the module starts, use menu bar → Force Network Detection to re-run the audit by hand. Check menu bar → View Logs for the applied rule and any step that failed.

**Log file location**: `~/.hammerspoon/wifi_autoconfig/wifi_autoconfig.log` (entries older than 7 days are pruned automatically)

## License

MIT