# Changelog

[English](CHANGELOG.md) | [简体中文](CHANGELOG.zh-CN.md)

All notable changes to **Wi-Fi AutoConfig for Hammerspoon** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.2.1] - 2026-10-03

### Fixed

- **Force-apply now validates before touching the system** — the editor's "force apply" action called `applyConfigToInterface` directly, so a malformed IP / netmask / gateway typed into the editor was pushed straight to `sudo networksetup` under the passwordless sudoers rule, with no validation and no rollback. The force-apply path now runs the same `validateConfig()` check as the save path and refuses invalid input with an alert.
- **IPv6 prefix label in the apply-result popup** — the popup called `i18n.t("label_prefix")`, a key that exists in neither language table, so the line rendered as the bare string `label_prefix: <value>`. It now uses `menu_label_prefix`, matching the status menu.
- **Command output no longer floods the log** — `runWithSudo` truncates command output at 2000 bytes before writing it to the log (a runaway command could previously append megabytes).
- **An unreadable `config.json` can no longer erase your policies** — `hs.json.decode` returns `nil` instead of raising, so one stray comma from a hand-edit decoded to nothing, the module continued from an empty table, and the next save wrote that empty table over the whole file. It also made every later switch fall through to "no policy found", which forces the interface onto DHCP and takes a static network offline. A file that does not parse is now left untouched on disk, the last good table stays in memory, all writes are refused until it parses again, automatic switching is skipped, and a modal dialog blocks until the user has acted: **Retry** re-reads the file in place, so fixing the syntax needs no Hammerspoon reload, while **Handle it later** keeps the safe state without nagging on the same unchanged bytes again.
- **A refused save or delete no longer makes the editor and the file disagree** — while `config.json` was unreadable the write was rejected, but the in-memory table had already been updated, so the editor displayed a policy the file did not contain and the next read silently reverted it. The change is now rolled back, and the failure is reported with a blocking dialog instead of a banner that fades after eight seconds.
- **Force-apply no longer decodes the URL payload twice** — `hs.urlevent` already percent-decodes `params.data`, and the handler decoded it a second time, so any literal `%XX` sequence in an SSID or address was mangled before `json.decode`, which then returned `nil`: pressing "force apply" did nothing at all, silently. The save path had always decoded once; both paths now agree.
- **A `dns` value written as a JSON array no longer breaks switching** — `isValidDNSEntry`/`setDNSServers` used the field as a string, so an array raised `bad argument #1 to 'gmatch'` halfway through an apply and left the interface partly configured. Arrays are now flattened to a comma-separated string on read and on save.
- **IPv6 is no longer disabled by policies that say nothing about it** — every case that was not `manual` with complete arguments fell into the final `else` and ran `-setv6off`, so a policy saved before `v6mode` existed, or hand-edited without that field, turned IPv6 off on every single switch while the "no policy at all" path left it alone. Only an explicit `"off"` disables it now; a missing or unrecognised mode is logged and skipped, and `configureIPv6` returns applied/skipped/failed/incomplete/unknown so callers can report the difference.
- **Failed network changes are reported instead of "success"** — every `runWithSudo` return value was discarded, and because `io.popen` gives sudo no terminal, a missing sudoers rule means the command fails outright rather than prompting. The apply sequence now collects each failing step (recognising the "a password is required" case and naming the missing rule), the notification says steps did not complete, and the popup is titled "partially applied" with the list. The README claim that Hammerspoon would prompt for a password on first use was wrong and has been corrected.
- **Editor: English labels were Chinese** — `ip_address`, `subnet_mask`, `router`, `prefix_length` and `dns_servers` still held CJK text in the `en` table, so an English interface showed mixed-language field labels.
- **Editor: saving no longer jumps the selection back to the first row** — the list rebuild ended with an unconditional `items[0].click()`, so after a save the selection moved to another network and the values you had just typed disappeared. The previously selected row is now re-selected by SSID, with the first row used only on the initial render.
- **Editor: the live lease is no longer copied into the static fields behind your back** — the current IP/netmask/gateway/DNS were auto-filled whenever the manual section was rendered for the connected SSID, including during a refresh, so a policy you only glanced at could be saved as static. The fill now happens only when you switch the dropdown to Manual yourself. The localized "system auto" DNS label is no longer offered as a DNS value.
- **Uninstall left a root privilege behind** — `uninstall.sh` never removed `/etc/sudoers.d/hammerspoon_wificonfig`, so the passwordless `networksetup` rule kept working after the module was gone. The uninstaller now owns that file (plus the legacy names), shows it, and removes it.
- **Uninstall could delete unrelated lines from `init.lua`** — the cleanup pattern was case-insensitive and matched on loose substrings, so any of your own lines mentioning the module name were dropped without a trace and without a backup. It now matches only the anchored `require` line and the injected comment, prints the lines it is about to remove, and saves `init.lua` first.
- **Uninstaller banner was stuck on an old version** — it printed `v3.0.0` long after the module moved on; it now reads `MODULE_VERSION` from `install.sh`, the same source `build-release.sh` uses.
- **Duplicate `networksetup -getinfo` per status read** — the report and the editor sync each spawned the same process twice, once for IPv4 and once for IPv6; both now use `getCurrentIPInfo()`, which parses one output for both families.
- **A `config.json` that disappears is no longer read as "no policies"** — with policies still loaded in memory, a deleted or zero-byte file decoded to nothing, the module rebuilt an empty file in its place, and every later switch then hit the "no policy found" branch, which forces the interface onto DHCP and costs a static network its address. Those two shapes are now treated as a loss to recover from: the loaded policies stay in memory, writing stays refused and automatic switching stays skipped until the file is back, and a dialog offers **Retry** (re-reads in place, no reload) or **Handle it later** (keeps the safe state without interrupting you again for the same absence). A real first run, with nothing loaded yet, still rebuilds the file silently, and reloading after you delete it on purpose gives the same clean start.
- **Only one modal dialog can be open** — `hs.dialog.blockAlert` runs a nested modal loop, and a second one raised by a URL event, a timer or another Wi-Fi switch while the first is still waiting for an answer leaves Hammerspoon with a window no button can dismiss. Every blocking dialog now goes through `utils.blockAlertOnce()`: a request that arrives while one is open is logged and answered with "not confirmed", which is what each caller already treats as a declined action. A dialog that raises still releases the guard, so a failure cannot wedge the module shut.
- **A stored policy is checked again on the way to `sudo`** — validation had only ever run when the editor saved. A policy that arrived by hand-edit, or was written by an older version that stored fewer fields, went straight into `networksetup` under the passwordless rule: an unknown `mode` was applied as static with no gateway, an absent gateway travelled as the literal text `nil` because the argument is positional, and a `v6mode` outside the three known values reached the interface. Every policy is revalidated immediately before it is applied, an unusable one is skipped with a notification and a log line naming the SSID and the field, the interface keeps what the system gave it, and an entry with no `mode` is read as `dhcp`.
- **An incomplete manual IPv6 policy is skipped as a set, and says so** — an address, prefix and router are one command, so a policy missing any of them used to be a choice between sending `nil` and leaving a half-configured IPv6 address on the interface. The whole policy is now skipped, and both that case and an unrecognised `v6mode` appear in the result popup's list of steps that did not complete instead of being reported as success.
- **An apply sequence that is still waiting no longer touches a moved-on interface** — the sequence waits up to 15s for DHCP, 10s for a static address and 5s for DNS, and a Wi-Fi switch during one of those waits starts a second sequence whose waits resume whenever they like; the stale one then wrote the previous network's DNS servers and IPv6 settings onto the interface that had already changed. Each sequence carries a token and rechecks it before every step after a wait, so a superseded sequence stops touching the network and stops reporting.
- **The editor survives a failed `hs.json.encode`** — encode returns `nil` rather than raising, and both the initial page load and a refresh spliced that value straight into `let networks = <json>;`, so the editor either broke on its own script or went on showing a stale list with no indication why. Both calls now fall back to an empty list or object and log the failure.

### Changed

- **`%admin` is no longer a supported sudoers subject** — machines whose rule was written by an earlier pre-release build of this installer have it narrowed to the current user on the next install run.
- **Removed unused helpers** — `utils.executeWithRetry()` (no caller), `init.refreshMenuBar()` (no caller), `core.getCurrentIPv6Info()` (superseded by `getCurrentIPInfo()`), the unreachable `wifi.interfaceDetails()` branch in `getCurrentWiFiStatus()`, and the duplicate `M.VERSION` in `i18n.lua`; `init.lua` and `install.sh` remain, documented as having to agree.
- **Argument quoting** — the `ifconfig <device>` and `tail -30 <log path>` command lines are now built with `shellQuote()` like every other shell invocation.
- **Passwordless sudoers rule renamed and scoped** — the installer now writes `/etc/sudoers.d/hammerspoon_wificonfig` (was `hammerspoon_netconfig`, only one or two characters away from the `hammerspoon_network` rule other tools may leave behind, which made auditing ambiguous). The rule is also narrowed from granting the whole `networksetup` binary to just the subcommands this module runs: `setmanual`, `setdhcp`, `setdnsservers`, `setv6manual`, `setv6automatic`, `setv6off`, plus the read-only `listallnetworkservices` the installer uses for its detection probe. The rule is granted to the single user who ran the installer and never to `%admin` (a passwordless `-setdnsservers` reachable by every admin account is a DNS-hijack primitive that outlives this module), and the installer verifies with a passwordless probe that the rule actually took effect instead of only reporting that a file was written. When the existing file grants the commands to a group, the installer rewrites it for the current user rather than treating it as "already configured".
- **Legacy sudoers files are shown, not just named** — when the installer finds `/etc/sudoers.d/hammerspoon_netconfig` or `hammerspoon_network`, it now prints the file's contents, lists which of the required subcommands that rule does **not** cover (an older rule typically omits `setv6manual`, which then fails outright when switching to manual IPv6, since sudo has no terminal to prompt in), and then gives the `sudo rm` command. The files are never removed automatically.

- **Over-wide sudoers leftovers are narrowed, and only the installer's own files are deleted** — drop-ins in `/etc/sudoers.d` are OR-ed, so a wide leftover keeps granting what it grants no matter how narrow the new file is. The installer now reads every drop-in that mentions `networksetup`, classifies it (a `%group` subject, or the bare binary with no subcommand), and treats a match as work to do rather than as "already configured", so the machine ends with a per-user, per-subcommand grant instead of the `%admin` or whole-binary rules that pre-release and v3.1.0 builds wrote. Deletion is limited to files carrying the marker line `install.sh` writes, and only after the new rule has been verified, so a drop-in belonging to another tool - or one the installer cannot read without a password - is printed and reported, never removed, and never left as the only reason the probe passed.
- **The sudoers rule is staged, validated and then moved into place** — the rule is written to a dotted temporary file next to the destination, checked with `visudo -cf` and only then renamed atomically, because an interrupted `cp` straight into `/etc/sudoers.d` leaves a truncated file that makes sudo reject the machine's whole configuration. The generated rule is validated before that too, and a write failure reports the command to run by hand instead of claiming the rule is installed.
- **The installer does not create the passwordless rule when there is nobody to answer** — over a pipe (`curl | bash`, a CI step) the question used to be printed and then answered yes on your behalf, so a standing grant that outlives both the installer and the module appeared without anyone agreeing to it. It now reports that the rule was not added, prints the `sudo visudo -f` command that adds it by hand, and, when an over-wide leftover was the reason the probe passed, names the file that still grants it. The old path rarely achieved anything either: without a terminal sudo cannot prompt for the password the write needs, so it usually ended in a confusing failure.
- **Release builds are tied to a tag** — `build-release.sh` reads `MODULE_VERSION` from `install.sh` and refuses to produce an archive unless a git tag matches that version, warning when HEAD is not the tagged commit. A bundle named v3.2.1 that no tag points at is indistinguishable from the code the tag holds once it is on a release page, and an install script downloading `vX.Y.Z` then has no way to say which bytes arrived. It also reports whether the generated `release.html` / `RELEASE.md` differ from the committed copies.
- **The uninstallers stop when there is nobody to ask** — `uninstall.sh` and `legacy-uninstall.sh` prompt through `/dev/tty` after checking that a terminal is really attached (a readable test on `/dev/tty` passes even when nothing is behind it), and with no terminal they explain and stop rather than guessing answers; running under `curl | bash` no longer has its remaining steps eaten by a `read` that consumed the script body. `init.lua` is backed up before its `require` line is removed, and a reference the patterns do not recognise - an assignment form, for example - is reported with the line printed rather than rewritten.

## [3.2.0] - 2026-10-03

### Added

- **Self-drawn status panel** — the menu-bar status view is now a custom borderless WebKit panel instead of a native `NSMenu`. This pins a single dark palette for both light and dark appearance (the amber and green were unreadable on the macOS menu material) and lets the informational rows stay inert on hover. It falls back to the native menu automatically if the webview cannot be created.

### Changed

- **Background status polling** — the network snapshot (Wi-Fi, IP, DNS, VPN) is now refreshed on a 5s background timer instead of synchronously on every menu open, so opening the status menu is instant instead of blocking on ~20 shell processes.
- **Lighter VPN detection** — the Clash-compatible API probes are skipped entirely unless a Clash-family process (Clash / FlClash / sing-box / mihomo / Karing) is actually running, and the probe timeout was lowered from 1s to 0.3s.

### Fixed

- **System-freezing event tap** — hover tracking no longer installs a `mouseMoved` CGEventTap (that tap froze the system pointer machine-wide); it now polls `hs.mouse.getAbsolutePosition()` on a timer, which cannot freeze the pointer.
- **Panel lifecycle** — the panel's webview, event tap, and timers are torn down on Hammerspoon reload/shutdown, preventing zombie windows from accumulating across Reload Config.
- Removed the unused `force_apply_network` URL handler (the editor only uses `force_apply_network_with_confirm`).
- Version strings in `init.lua` / `i18n.lua` are aligned with `install.sh` (now 3.2.0).

## [3.1.0] - 2026-09-30

### Added

- **Passwordless sudo setup** — `install.sh` now offers to write a passwordless sudoers rule to
  `/etc/sudoers.d/hammerspoon_netconfig` (`<user> ALL=(ALL) NOPASSWD: /usr/sbin/networksetup`) so
  network switches run silently. It is skipped automatically when passwordless sudo is already
  configured, and the rule is validated with `visudo -cf` before writing.

### Fixed

- **WebView injection** — SSID values and editor config/network JSON are now HTML-escaped
  (`escapeHtml`) and inline-script-escaped (`</script>` → `\u003c/script\u003e`) before being injected
  into the editor popup, closing a local HTML-injection vector from attacker-controlled SSID names.
- **IPv6 validation** — `config.lua` now validates IPv6 address, prefix length (1–128) and gateway in
  `manual` v6 mode, with matching error messages in both locales.
- **DNS active-check** — the post-apply DNS verification now uses exact set membership instead of
  substring matching, so `8.8.8.8` is no longer falsely reported as active when the real value is
  `8.8.8.88`.
- **IPv6 report** — the network report now includes the IPv6 prefix length and gateway.

## [3.0.0] - 2026-09-29

### Added

- **Offline release bundle** — `scripts/build-release.sh` packages `src/`, `scripts/` and
  all docs into a single `wifi-autoconfig-hammerspoon-vX.Y.Z.zip` for fully offline installs.
- **Standalone release page** — `release.html` (dark theme) plus `RELEASE.md` release notes,
  both generated by the build script.
- **Local/offline install mode** — `install.sh` now detects when it is run from inside the
  extracted archive and installs from the bundled files instead of downloading from GitHub.
- **Legacy upgrade / uninstall scripts** — `legacy-install.sh` (clean a pre-3.0 install then
  install v3.0.0 in one step) and `legacy-uninstall.sh` (remove a pre-3.0 install only).

### Changed

- **Unified backup location** — config backups now go to `~/.wifi_autoconfig_backups/`
  (overridable via the `BACKUP_DIR` environment variable) instead of the Desktop, which also
  removes the failure when no `~/Desktop` exists.
- Bumped module version to `3.0.0` (installer, uninstaller, `init.lua`, `i18n.lua`).

## [1.0.0] - 2026-09-28

First public release. Installs to `~/.hammerspoon/wifi_autoconfig/` and is loaded with
`require("wifi_autoconfig.init")`.

### Added

- **SSID-based auto switching** — `hs.wifi.watcher` detects Wi-Fi changes and applies the matching profile.
- **Per-SSID profiles** — static IP / DHCP / custom DNS / IPv6 (`automatic`, `manual`, `off`) per network.
- **Global fallback** — the `__DEFAULT__` profile covers any unconfigured SSID.
- **WebView editor** — HTML/CSS panel for managing profiles, with live hardware status sync.
- **Force apply** — push editor contents straight to the interface, with a confirmation dialog showing the full config.
- **Menu bar integration** — settings, logs, DHCP reset and force re-detection, with live Wi-Fi / IPv4 / IPv6 / DNS / VPN status.
- **Bilingual UI (zh/en)** — auto-detected via `hs.host.locale`; the module, the editor and the installer all follow it.
- **7-day log rotation** — `wifi_autoconfig.log` is pruned automatically on write.
- **Config validation** — IPv4 / netmask / gateway / DNS format checks before saving.
- **Installer & uninstaller** — `install.sh` (fresh / `--update` / `--force` / `--proxy`) and `uninstall.sh`.

### Changed

- Log file renamed to `wifi_autoconfig.log`.
- Menu bar rebuilds now reuse a 5-second status cache, so repeated clicks no longer re-fork the same
  two dozen shell probes.
- Dark-mode detection (`defaults read`) is cached for 5 seconds.

### Removed

- All pre-1.0 compatibility shims: the legacy `wifi_ip_config.json` / `wifi_ip_switcher.log`
  migration paths are gone. The installer deletes any pre-1.0 directory and strips its
  `require` line from `init.lua` instead of migrating it.
