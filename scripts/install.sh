#!/bin/bash
#
# install.sh - One-command installer for Wi-Fi AutoConfig for Hammerspoon
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash
#   bash install.sh              # Fresh install
#   bash install.sh --update     # Update code only (preserves config.json)
#   bash install.sh --proxy URL  # Use a specific GitHub proxy (skips auto mirror test)
#   bash install.sh --help       # Show help
#
# Mirror handling for users in mainland China:
#   When no proxy is given, the installer speed-tests several built-in GitHub
#   mirrors and (if run in an interactive shell) lets you pick one; otherwise it
#   auto-selects the fastest. To force a mirror, set GITHUB_PROXY:
#     GITHUB_PROXY=https://ghfast.top/ bash install.sh
#   Downloaded release archives are SHA-256 verified against scripts/checksums.txt.
#
set -e

# ============================================================================
# Configuration
# ============================================================================
GITHUB_USER="imonior"
GITHUB_REPO="wifi-autoconfig-hammerspoon"
GITHUB_BRANCH="main"
MODULE_VERSION="3.2.9"

# GitHub proxy support (for users in China)
# Usage: GITHUB_PROXY=https://ghfast.top/ bash install.sh
#   or:  bash install.sh --proxy https://ghfast.top/
GITHUB_PROXY="${GITHUB_PROXY:-}"

HAMMERSPOON_APP="/Applications/Hammerspoon.app"
HAMMERSPOON_DIR="$HOME/.hammerspoon"
HAMMERSPOON_INIT="$HAMMERSPOON_DIR/init.lua"
INSTALL_DIR="$HAMMERSPOON_DIR/wifi_autoconfig"
REQUIRE_LINE='require("wifi_autoconfig.init")'
REQUIRE_COMMENT='-- Wi-Fi AutoConfig for Hammerspoon'

# Set by ensure_sudoers_rule from a real passwordless probe, not from the presence
# of a file: a sudoers drop-in that does not match the running account is not a
# working rule, and the success banner must not claim otherwise.
SUDOERS_EFFECTIVE=""

# Only a live require of this module counts as "already installed", in either form
# people write it (bare, or assigned to a variable). A bare search for the module
# name also matches a user's own comment, a log path or a require of a similarly
# named module, and the installer would then skip the injection while reporting the
# module as configured. A commented-out require does not load anything, so the line
# must start with the require itself or with an assignment that ends in it.
REQUIRE_PATTERN='^[[:space:]]*((local[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*([[:space:]]*,[[:space:]]*[A-Za-z_][A-Za-z0-9_]*)*[[:space:]]*=[[:space:]]*)?require[[:space:]]*\(?[[:space:]]*["'\'']wifi_autoconfig\.init["'\'']'

HAMMERSPOON_DMG_URL="https://github.com/Hammerspoon/hammerspoon/releases/download/1.1.1/Hammerspoon-1.1.1.zip"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Helpers
# ============================================================================
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# Prepend GITHUB_PROXY to any GitHub URL
github_url() {
    if [ -n "$GITHUB_PROXY" ]; then
        echo "${GITHUB_PROXY}${1}"
    else
        echo "$1"
    fi
}

cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

# ============================================================================
# GitHub mirror discovery (China-friendly, opt-in via auto speed test)
# ============================================================================
# Built-in candidate mirrors. Used ONLY when the user does not pass an explicit
# GITHUB_PROXY (env) or --proxy flag. Prefix-style: <mirror>/<target-url>.
# Each is reachability- and speed-tested at run time, so a dead or slow one is
# simply skipped. (mirror.ghproxy.com was dropped: its TLS chain fails certificate
# verification on stock clients, so it could never be selected anyway.)
# 内置候选镜像。仅当用户未显式传 GITHUB_PROXY（环境变量）或 --proxy 时使用。形式为
# <镜像>/<目标URL> 前缀。运行时会逐个测可达性与速度，失效或慢的会被自动跳过。
# （mirror.ghproxy.com 已移除：其 TLS 证书链在原生客户端上校验失败，本就无法被选中。）
MIRROR_CANDIDATES=(
    "https://gh-proxy.com"
    "https://ghfast.top"
    "https://ghproxy.net"
)
# A tiny, always-present file used to measure each mirror's latency.
MIRROR_PROBE_PATH="scripts/install.sh"

# Probe every candidate mirror; print "<latency> <mirror>" lines, best first.
probe_mirrors() {
    local m t
    local out=()
    for m in "${MIRROR_CANDIDATES[@]}"; do
        t=$(curl -fsS -m 5 -r 0-0 -o /dev/null -w '%{time_total}' \
            "${m}/https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}/${MIRROR_PROBE_PATH}" 2>/dev/null) || continue
        case "$t" in ''|*[!0-9.]*) continue ;; esac
        out+=("${t} ${m}")
    done
    if [ ${#out[@]} -gt 0 ]; then
        printf '%s\n' "${out[@]}" | sort -n
    fi
    return 0
}

# Return direct GitHub latency (empty string if unreachable).
probe_direct() {
    curl -fsS -m 5 -r 0-0 -o /dev/null -w '%{time_total}' \
        "https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}/${MIRROR_PROBE_PATH}" 2>/dev/null || true
}

# Pick a download source: interactive when a TTY is available, else the fastest.
# Does nothing if GITHUB_PROXY was already set explicitly by the caller.
select_mirror() {
    local results direct_lat choice i line label direct_idx
    results="$(probe_mirrors)"
    direct_lat="$(probe_direct)"

    if [ -z "$results" ] && [ -z "$direct_lat" ]; then
        warn "No GitHub mirror or direct connection reachable; will try direct anyway."
        GITHUB_PROXY=""
        return 0
    fi

    echo ""
    info "GitHub download source speed test (lower is better):"
    i=1
    if [ -n "$results" ]; then
        while IFS= read -r line; do
            label="${line#* }"
            echo "  [$i] ${label}/   (${line%% *}s)"
            i=$((i + 1))
        done <<< "$results"
    fi
    if [ -n "$direct_lat" ]; then
        echo "  [$i] Direct GitHub   (${direct_lat}s)"
        direct_idx=$i
        i=$((i + 1))
    fi
    echo "  [0] Direct GitHub (no mirror)"
    echo ""

    if [ -t 1 ] && [ -t 0 ]; then
        printf 'Select a download source [1-%d, 0=direct, default=fastest]: ' "$((i - 1))"
        read -r choice || choice=""
    else
        choice=""
        info "Non-interactive shell detected; auto-selecting the fastest source."
    fi

    if [ -z "$choice" ]; then
        if [ -n "$results" ]; then
            line=$(printf '%s\n' "$results" | head -1); label="${line#* }"
        else
            label="direct"
        fi
    elif [ "$choice" = "0" ]; then
        label="direct"
    elif [ -n "$direct_lat" ] && [ "$choice" = "$direct_idx" ]; then
        label="direct"
    else
        line=$(printf '%s\n' "$results" | sed -n "${choice}p" 2>/dev/null) || true
        if [ -n "$line" ]; then label="${line#* }"; else label="direct"; fi
    fi

    if [ "$label" = "direct" ]; then
        GITHUB_PROXY=""
        info "Using direct GitHub."
    else
        GITHUB_PROXY="${label}/"
        info "Using mirror: ${GITHUB_PROXY}"
    fi
}

# ============================================================================
# Archive integrity
# 归档完整性
# ============================================================================
# Print the SHA-256 of a file with whichever tool the host provides. macOS ships
# shasum and openssl but NOT the GNU sha256sum, so hard-coding one tool would abort
# the install on a stock Mac.
# 用宿主机可用的任一工具打印文件 SHA-256。macOS 自带 shasum/openssl，但没有 GNU 的
# sha256sum；若写死单一工具，会在原生 Mac 上直接中止安装。
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}'
    fi
}

# Verify a downloaded release tarball.
# For a tagged release we compare its SHA-256 against the value published in
# scripts/checksums.txt, fetched from DIRECT GitHub so a compromised mirror cannot
# also fake the checksum. When direct GitHub is unreachable (common behind the GFW)
# we fall back to reading the archive's own MODULE_VERSION, and warn that the file
# was NOT hash-verified. A branch install has neither a checksum nor a fixed version
# to compare against, so it is only checked for carrying a version at all.
# 校验下载到的发布压缩包：tag 发布时把 SHA-256 与 scripts/checksums.txt 公布的值比对，
# 且该校验和从「直连 GitHub」获取，防止被污染的镜像连校验和一起伪造。直连不可达时回退为
# 读取压缩包内的 MODULE_VERSION，并明确告警「未做哈希校验」。分支安装既无校验和也无固定
# 版本号可比，只校验其确实带有版本号。
verify_tarball() {
    local tarball="$1" ref="$2" actual expected sumfile member ver
    actual=$(sha256_of "$tarball")
    if [ -z "$actual" ]; then
        error "Could not compute a checksum of the downloaded archive."
        return 1
    fi

    # Tag release: authoritative SHA-256 check against the published checksum.
    # tag 发布：与公布校验和做权威比对。
    if [[ "$ref" == v* ]]; then
        local sum_url="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${ref}/scripts/checksums.txt"
        sumfile=$(curl -fsSL -m 8 "$sum_url" 2>/dev/null) || sumfile=""
        expected=""
        if [ -n "$sumfile" ]; then
            expected=$(printf '%s\n' "$sumfile" | awk -v r="$ref" '$1 == r { print $2; exit }')
        fi
        if [ -n "$expected" ]; then
            if [ "$actual" = "$expected" ]; then
                info "Integrity verified: SHA-256 matches the published checksum for ${ref}."
                return 0
            fi
            error "Integrity check FAILED for ${ref}: checksum mismatch."
            error "  expected: $expected"
            error "  actual  : $actual"
            return 1
        fi
        warn "Published checksum for ${ref} could not be fetched (direct GitHub unreachable)."
        warn "Falling back to an embedded-version check only - the archive was NOT hash-verified."
    fi

    # Embedded-version sanity check. Locate install.sh by listing the archive: a
    # tag archive names its root dir after the tag (dropping the leading "v") while
    # a branch archive keeps the branch name, so neither path can be guessed.
    # MODULE_VERSION is the single source of truth.
    # 内嵌版本号健全性检查。通过列出归档内容定位 install.sh：tag 归档的根目录名会去掉开头
    # 的 "v"，而分支归档保留分支名，二者都无法可靠猜测。MODULE_VERSION 是唯一版本来源。
    member=$(tar tzf "$tarball" 2>/dev/null | grep -m1 -E '(^|/)scripts/install\.sh$')
    ver=""
    if [ -n "$member" ]; then
        ver=$(tar xzf "$tarball" -O "$member" 2>/dev/null \
                | grep -m1 -E '^MODULE_VERSION=' | sed 's/.*="//; s/"$//')
    fi
    if [ -z "$ver" ]; then
        error "Could not read MODULE_VERSION from the downloaded archive."
        return 1
    fi

    if [[ "$ref" == v* ]]; then
        if [ "$ver" = "${ref#v}" ]; then
            info "Embedded version matches target (${ver})."
            return 0
        fi
        error "Version mismatch: downloaded archive reports v${ver}, expected ${ref#v}."
        return 1
    fi

    # Branch install: no fixed version to compare against.
    # 分支安装：没有可比的固定版本号。
    info "Branch archive reports version v${ver} (no checksum is published for branches)."
    return 0
}

show_help() {
    cat <<'EOF'
Wi-Fi AutoConfig for Hammerspoon installer

Usage:
  bash install.sh              Fresh install (installs Hammerspoon if missing)
  bash install.sh --update     Update code only, preserves your config.json
  bash install.sh --force      Overwrite existing installation without prompting
  bash install.sh --proxy URL  Use a specific GitHub proxy (skips the auto mirror test)
  bash install.sh --branch BR  Install from a branch instead of the release tag
  bash install.sh --help       Show this help message

One-liner (curl | bash):
  curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash

  Mirror auto-selection (mainland China):
  With no proxy set, the installer speed-tests several built-in GitHub mirrors and,
  in an interactive shell, lets you pick one; otherwise it auto-selects the fastest.
  Downloaded release archives are SHA-256 verified against scripts/checksums.txt.

  Force a specific mirror:
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | GITHUB_PROXY=https://ghfast.top/ bash

  With update:
  curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash -s -- --update

  With mirror + update:
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | GITHUB_PROXY=https://ghfast.top/ bash -s -- --update

Environment variable:
  GITHUB_PROXY=https://ghfast.top/ bash install.sh
EOF
}

# ============================================================================
# Step 1: Check OS
# ============================================================================
check_os() {
    if [ "$(uname)" != "Darwin" ]; then
        error "This tool requires macOS. Detected: $(uname)"
        exit 1
    fi
    info "macOS detected: $(sw_vers -productVersion)"
}

# ============================================================================
# Step 2: Check / Install Hammerspoon
# ============================================================================
ensure_hammerspoon() {
    if [ -d "$HAMMERSPOON_APP" ]; then
        info "Hammerspoon is already installed."
        return 0
    fi

    step "Hammerspoon not found. Installing..."

    # Try Homebrew first
    if command -v brew &> /dev/null; then
        info "Homebrew detected. Installing via brew..."
        brew install --cask hammerspoon
    else
        info "Homebrew not found. Downloading from official release..."

        # Fetch latest release URL from GitHub API (fallback to hardcoded version)
        local hammerspoon_url
        local api_url
        api_url=$(github_url "https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest")
        hammerspoon_url=$(curl -fsSL "$api_url" 2>/dev/null \
            | grep '"browser_download_url"' \
            | grep '\.zip"' \
            | head -1 \
            | sed 's/.*"browser_download_url": *"//;s/"$//')

        # Apply proxy to the download URL if needed
        if [ -n "$hammerspoon_url" ] && [ -n "$GITHUB_PROXY" ]; then
            hammerspoon_url="${GITHUB_PROXY}${hammerspoon_url}"
        fi

        if [ -z "$hammerspoon_url" ]; then
            warn "Could not fetch latest release URL. Falling back to known version."
            hammerspoon_url=$(github_url "$HAMMERSPOON_DMG_URL")
        fi

        local tmp_zip="/tmp/hammerspoon.zip"
        info "Downloading Hammerspoon from: $hammerspoon_url"
        curl -fsSL -o "$tmp_zip" "$hammerspoon_url"
        info "Extracting..."
        unzip -o "$tmp_zip" -d /tmp/ > /dev/null 2>&1
        info "Installing to /Applications..."
        cp -R /tmp/Hammerspoon.app /Applications/
        rm -f "$tmp_zip"
        rm -rf /tmp/Hammerspoon.app
    fi

    if [ ! -d "$HAMMERSPOON_APP" ]; then
        error "Failed to install Hammerspoon. Please install manually from https://hammerspoon.org"
        exit 1
    fi

    info "Hammerspoon installed successfully."
}

# ============================================================================
# Step 3: Ensure ~/.hammerspoon exists (launch Hammerspoon once)
# ============================================================================
ensure_hammerspoon_dir() {
    if [ -d "$HAMMERSPOON_DIR" ]; then
        return 0
    fi

    step "Initializing Hammerspoon (first launch)..."
    open "$HAMMERSPOON_APP"

    local waited=0
    while [ ! -d "$HAMMERSPOON_DIR" ] && [ $waited -lt 15 ]; do
        sleep 1
        waited=$((waited + 1))
    done

    if [ ! -d "$HAMMERSPOON_DIR" ]; then
        error "Hammerspoon did not create ~/.hammerspoon directory."
        error "Please launch Hammerspoon manually from Applications, then re-run this script."
        exit 1
    fi

    info "Hammerspoon directory initialized."
}

# ============================================================================
# Step 2b: Ensure passwordless sudo rule for /usr/sbin/networksetup
#   The module changes IP / DNS / DHCP / IPv6 via `sudo /usr/sbin/networksetup`.
#   Without a NOPASSWD sudoers rule, every network switch would prompt for a
#   password. On a fresh machine there is none, so we offer to install one.
#
#   The rule is scoped twice: to the exact subcommands this module invokes (see
#   SUBCOMMANDS below) rather than the whole binary - networksetup can also
#   delete services and change proxies, which this module never does - and to
#   the single user running the installer rather than an admin group.
#
#   Filename note: older installs used hammerspoon_netconfig, and machines that
#   were set up by hand often carry hammerspoon_network. Both are one or two
#   characters apart, which makes auditing ambiguous. The installer now manages
#   hammerspoon_wificonfig, which matches the project name, and dumps the
#   contents of any older file it finds so you can compare before removing.
#   uninstall.sh removes the file this installer writes.
# ============================================================================
# The drop-in directory, in one place so the scan below stays testable without
# pointing at the real /etc.
SUDOERS_D="/etc/sudoers.d"
SUDOERS_FILE="$SUDOERS_D/hammerspoon_wificonfig"
LEGACY_SUDOERS_FILES="$SUDOERS_D/hammerspoon_netconfig $SUDOERS_D/hammerspoon_network"

# Every networksetup subcommand the module runs under sudo. Keep this in sync
# with src/core.lua and src/network_apply.lua.
# -listallnetworkservices is read-only and is here because ensure_sudoers_rule()
# probes with it to decide whether the rule is already in place; without it the
# probe would prompt for a password and look like "not configured". It is granted
# without an argument pattern; see SUBCOMMANDS_NOARGS below.
SUBCOMMANDS="setmanual setdhcp setdnsservers setv6manual setv6automatic setv6off listallnetworkservices"

# Written into every drop-in this installer creates, and the only reason a later run
# is allowed to delete one: a sudoers file with a similar name that this project never
# wrote may belong to another tool, so it is shown and advised on instead. Released
# builds wrote "# Generated by install.sh on <date>" and the current form adds the
# user, so this prefix is matched rather than a whole line.
SUDOERS_MARKER='# Generated by install.sh'

# networksetup subcommands that take no arguments. sudoers matches a command's
# arguments one pattern at a time, so `-listallnetworkservices *` asks for a second
# argument the call does not have: on a machine carrying exactly that grant the bare
# call was refused, while the same call with one extra token was accepted.
# passwordless_probe() makes the bare call and verify_sudoers_rule() re-runs it after
# writing, so that wildcard made a working rule read as unconfigured and a 3.2.1
# install ended with "switches will fail, not prompt" - switching itself was fine all
# along, because every call the module makes carries the interface name and matched
# `-setdhcp *` and friends. Granting the subcommand with no trailing pattern is the
# shape the probe actually uses; re-checked live after installing the corrected rule,
# the bare call now runs without a password.
SUBCOMMANDS_NOARGS="listallnetworkservices"

build_sudoers_rule() {
    local rule_user="$1"
    local cmds="" sub pattern
    for sub in $SUBCOMMANDS; do
        if [ -n "$cmds" ]; then cmds="$cmds, "; fi
        pattern=" *"
        case " $SUBCOMMANDS_NOARGS " in
            *" $sub "*) pattern="" ;;
        esac
        # Wildcard the arguments: the interface name and values are quoted
        # single tokens, and sudoers matches each argument separately.
        cmds="${cmds}/usr/sbin/networksetup -${sub}${pattern}"
    done
    cat <<EOF
# Wi-Fi AutoConfig for Hammerspoon
# Allows silent network configuration changes for this user only, limited to the
# subcommands the module actually uses (IP / DNS / DHCP / IPv6).
${SUDOERS_MARKER} for user '${rule_user}' on $(date)
${rule_user} ALL=(root) NOPASSWD: ${cmds}
EOF
}

# The rule is granted to the running user and to nobody else. It is deliberately
# NOT granted to %admin: -setdnsservers/-setmanual run by every admin account on
# the machine, without a password, is a persistent DNS-hijack primitive that
# outlives this module (any local process running as that user can reach it).
# Keeping it per-user means the permission is exactly as wide as the person who
# asked for it, and uninstall.sh can take it back.
sudoers_rule_subject() {
    # `curl ... | sudo bash` is a documented way to run this script. whoami would
    # then be root, and the rule would grant the permission to root - which is
    # nobody's intent and covers no real account. SUDO_USER carries the human.
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        echo "$SUDO_USER"
    else
        whoami
    fi
}

# True when an existing rule is wider than anything this installer grants, and says
# how in SCOPE_PROBLEM. Two shapes qualify:
#   - a group (%admin came from a pre-release build of this installer): every admin
#     account on the machine gains silent DNS/IP changes, not just the one user who
#     ran the installer;
#   - the bare binary (what v3.1.0 wrote): /usr/sbin/networksetup with no
#     subcommand also grants -deletednetworkservices, -setmac, proxy changes and
#     more, none of which this module uses.
# Both are narrowed back to the current user and the listed subcommands here,
# BEFORE the passwordless probe below - either shape makes that probe succeed, and
# the installer would otherwise report "already configured" and leave the machine
# -wide grant in place forever.
sudoers_scope_problem() {
    local f="$1"
    SCOPE_PROBLEM=""
    read_sudoers_file "$f" || return 1
    classify_sudoers_content
}

# Same classification, on whatever is already in SUDOERS_CONTENT.
classify_sudoers_content() {
    SCOPE_PROBLEM=""

    # Only grant lines count: the header comments mention networksetup too, and
    # matching them would flag this installer's own, correctly scoped, file.
    local body
    body="$(grep -v '^[[:space:]]*#' <<< "$SUDOERS_CONTENT")"

    if grep -qE '^[[:space:]]*%[A-Za-z0-9_.-]+[[:space:]]+ALL=' <<< "$body"; then
        SCOPE_PROBLEM="it grants these commands to a whole GROUP, so every account in it can change DNS/IP without a password"
        return 0
    fi
    if grep -qE '/usr/sbin/networksetup[[:space:]]*(,|$)' <<< "$body"; then
        SCOPE_PROBLEM="it grants the WHOLE /usr/sbin/networksetup binary, including the subcommands this module never uses (delete service, proxy, MAC address)"
        return 0
    fi
    return 1
}

# Drop-ins this module may have written: the name it manages now, the names older
# builds used, and anything else in /etc/sudoers.d whose name points at this
# project (a hand-copied or renamed variant behaves the same way). Listing the
# directory needs no privilege; reading a file does, so an unreadable candidate is
# reported as unreadable rather than silently treated as safe.
sudoers_candidates() {
    local f
    for f in "$SUDOERS_FILE" $LEGACY_SUDOERS_FILES "$SUDOERS_D"/*hammerspoon* \
             "$SUDOERS_D"/*wificonfig* "$SUDOERS_D"/*networksetup*; do
        [ -f "$f" ] && echo "$f"
    done | sort -u
}

# Sets OVER_BROAD_FILE / SCOPE_PROBLEM from the first over-wide rule found, and
# UNREADABLE_SUDOERS to the candidates whose contents could not be read.
find_over_broad_sudoers() {
    local f
    OVER_BROAD_FILE=""
    SCOPE_PROBLEM=""
    UNREADABLE_SUDOERS=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if ! read_sudoers_file "$f"; then
            UNREADABLE_SUDOERS="$UNREADABLE_SUDOERS $f"
            continue
        fi
        if classify_sudoers_content; then
            OVER_BROAD_FILE="$f"
            return 0
        fi
    done <<< "$(sudoers_candidates)"
    return 1
}

# Reads a sudoers.d file into SUDOERS_CONTENT (root-owned 0440, so this may
# need a passwordless sudo). Returns 1 when the content could not be read, in
# which case the caller tells the user the command to run by hand.
read_sudoers_file() {
    local f="$1"
    SUDOERS_CONTENT=""
    if [ -r "$f" ]; then
        SUDOERS_CONTENT="$(cat "$f" 2>/dev/null)"
    elif sudo -n cat "$f" >/dev/null 2>&1; then
        SUDOERS_CONTENT="$(sudo -n cat "$f" 2>/dev/null)"
    elif has_tty; then
        # Drop-ins are root:wheel 0440, so a normal user cannot read them at all,
        # and `cat` is not in the passwordless rule. Asking once is the only way to
        # learn whether an existing file is group-wide - which is exactly the thing
        # this installer must not leave in place. Without a terminal sudo cannot
        # prompt, so nothing is read and the caller says so instead.
        SUDOERS_CONTENT="$(sudo cat "$f" </dev/tty 2>/dev/null)"
    fi
    [ -n "$SUDOERS_CONTENT" ]
}

dump_sudoers_content() {
    local line
    while IFS= read -r line; do
        echo "    | $line"
    done <<< "$SUDOERS_CONTENT"
}

# Shows every other drop-in in this project's name, verbatim, plus what is wrong
# with it: a shape wider than this installer grants, or subcommands it lacks (a
# missing -setv6manual makes that call fail outright, because sudo gets no terminal
# to prompt in).
report_legacy_sudoers() {
    local found="" f
    while IFS= read -r f; do
        case "$f" in
            ""|"$SUDOERS_FILE") continue ;;
        esac
        found="$found $f"
    done <<< "$(sudoers_candidates)"
    [ -z "$found" ] && return 0

    warn "Other sudoers drop-ins in this project's name, from earlier installs:"
    for f in $found; do
        warn ""
        warn "  $f:"
        if ! read_sudoers_file "$f"; then
            warn "    (could not read without a password - show it with: sudo cat $f)"
            continue
        fi
        dump_sudoers_content

        if classify_sudoers_content; then
            warn ""
            warn "  Wider than this installer ever grants, because $SCOPE_PROBLEM."
            continue
        fi

        local missing=""
        local sub
        for sub in $SUBCOMMANDS; do
            # The grant may end the line (a subcommand that takes no arguments is
            # written without a trailing wildcard), so the delimiter is space,
            # comma or end of line - matching only " " would report it as missing.
            if ! grep -qE -- "-${sub}([[:space:]]|,|$)" <<< "$SUDOERS_CONTENT"; then
                missing="$missing $sub"
            fi
        done
        if [ -n "$missing" ]; then
            warn ""
            warn "  It does NOT cover:$missing"
            warn "  Those commands will still ask for your password."
        fi
    done

    warn ""
    warn "This installer manages $SUDOERS_FILE (scoped to the subcommands above)."
    warn "Drop-ins carrying this project's own marker ('$SUDOERS_MARKER') are removed"
    warn "once the new rule is verified, because sudoers files are OR-ed: leaving an"
    warn "old one behind would keep the wider permission granted forever. Anything"
    warn "without that marker is only shown here, never touched - remove it yourself"
    warn "if it is yours:"
    for f in $found; do
        warn "    sudo rm $f"
    done
}

# Narrowing the grant is only real once the over-wide rule is gone: /etc/sudoers.d
# entries are OR-ed, so a leftover "%admin ... -setdnsservers *" keeps every admin
# account passwordless whatever this installer writes for one user. Removal is
# limited to files carrying the marker install.sh itself writes, so a drop-in some
# other tool (or the user) created is never deleted.
remove_over_broad_sudoers() {
    local f
    RESIDUAL_WIDE_FILES=""
    while IFS= read -r f; do
        case "$f" in
            ""|"$SUDOERS_FILE") continue ;;
        esac
        if ! read_sudoers_file "$f"; then
            warn "Cannot check $f without a password; leaving it in place."
            warn "Review it yourself: sudo cat $f"
            RESIDUAL_WIDE_FILES="$RESIDUAL_WIDE_FILES $f"
            continue
        fi
        classify_sudoers_content || continue
        if ! grep -qF "$SUDOERS_MARKER" <<< "$SUDOERS_CONTENT"; then
            warn "Leaving $f alone: it is over-wide ($SCOPE_PROBLEM) but not written"
            warn "by this installer, so it may belong to another tool."
            warn "Narrow or remove it yourself: sudo visudo -f $f"
            RESIDUAL_WIDE_FILES="$RESIDUAL_WIDE_FILES $f"
            continue
        fi
        if sudo rm -f "$f" 2>/dev/null; then
            info "Removed the wider rule an earlier build of this installer wrote: $f"
            info "The grant now covers only '$(sudoers_rule_subject)' and the listed subcommands."
        else
            warn "Could not remove $f (need root)."
            warn "Until it goes, the wider permission is still granted: sudo rm $f"
            RESIDUAL_WIDE_FILES="$RESIDUAL_WIDE_FILES $f"
        fi
    done <<< "$(sudoers_candidates)"
    return 0
}

# Is a terminal actually attached? /dev/tty keeps existing as a character device
# when nothing is behind it (curl | bash over ssh, a CI step, this script run from
# the module itself), and a readable test like `-c /dev/tty` still says yes - so the
# only honest check is to open it. Failed redirects are reported by the shell to its
# own stderr, which a command-level 2>/dev/null cannot hide, hence the subshell.
has_tty() {
    ( exec </dev/tty ) 2>/dev/null
}

# Ask a question even when the script itself arrived over a pipe (curl | bash),
# where stdin is the script body: a bare `read` there consumes the next command
# line as the answer and bash carries on after it, silently skipping steps.
# Returns 0 when the user was actually asked, 1 when there is nobody to ask.
ask_line() {
    local prompt="$1"
    REPLY=""
    if [ -t 0 ]; then
        read -r -p "$prompt" REPLY || true
        return 0
    elif has_tty && read -r -p "$prompt" REPLY </dev/tty 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Does the account that will run the module actually get these calls for free?
# Under `curl | sudo bash` the script is root, and root's sudo never asks, so a
# probe run as root would report success for a rule that covers nobody: ask as the
# rule's user instead.
passwordless_probe() {
    local rule_user
    rule_user="$(sudoers_rule_subject)"
    if [ "$(id -u)" -eq 0 ] && [ "$rule_user" != "root" ]; then
        sudo -n -u "$rule_user" sudo -n /usr/sbin/networksetup -listallnetworkservices >/dev/null 2>&1
    else
        sudo -n /usr/sbin/networksetup -listallnetworkservices >/dev/null 2>&1
    fi
}

ensure_sudoers_rule() {
    step "Checking passwordless sudo for network changes..."

    report_legacy_sudoers

    # Any rule wider than this installer's grant - a %admin group grant left by a
    # pre-release build, or the bare /usr/sbin/networksetup binary that v3.1.0 wrote
    # - is narrowed here, BEFORE the passwordless probe below. Either shape makes
    # that probe succeed, and the installer would then say "already configured" and
    # leave a permission that reaches far beyond this module in place forever.
    local narrow_existing=false
    if find_over_broad_sudoers; then
        warn "A sudoers rule is wider than this installer ever grants: $OVER_BROAD_FILE"
        warn "Reason: $SCOPE_PROBLEM"
        if [ "$OVER_BROAD_FILE" = "$SUDOERS_FILE" ]; then
            warn "That is the file this installer manages, so it is rewritten."
        else
            warn "This installer grants per-user, per-subcommand access only, so that"
            warn "file is reported here and, if this installer wrote it, removed once"
            warn "the new rule is verified."
        fi
        narrow_existing=true
    fi
    if [ -n "$UNREADABLE_SUDOERS" ]; then
        warn "Cannot tell whether these are over-wide without a password:$UNREADABLE_SUDOERS"
        warn "Check them yourself: sudo cat <file>"
    fi

    # Already passwordless for the account that will use it?
    if [ "$narrow_existing" != true ] && passwordless_probe; then
        SUDOERS_EFFECTIVE=true
        info "Passwordless sudo already in effect for '$(sudoers_rule_subject)'. Skipping."
        return 0
    fi

    warn "The passwordless probe failed: that read-only networksetup call needs a password."
    warn "A switch may then fail outright rather than prompt, because sudo has no terminal here."
    warn "This installer can add a passwordless sudoers rule so it stays silent, and will"
    warn "rewrite an existing one that does not answer the probe."
    warn "Scope: user '$(sudoers_rule_subject)', only these networksetup subcommands:"
    warn "         $SUBCOMMANDS"
    warn "         (not a group, so no other account gains it; uninstall.sh removes it)"
    echo ""
    if ask_line "Add this passwordless sudo rule now? (y/N) "; then
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            if [ "$narrow_existing" = true ]; then
                warn "Nothing was written, so the wider rule stays in $OVER_BROAD_FILE."
                warn "Narrow it yourself, or the broader permission keeps being granted:"
                warn "    sudo visudo -f $OVER_BROAD_FILE"
            else
                warn "Skipped. You can add it later or enter your password each time."
            fi
            return 0
        fi
    else
        # Nothing is written when nobody is there to agree to it. The rule is a
        # standing grant - it outlives the installer and the module - and over a
        # pipe (curl | bash, a CI step) the person running it has seen the
        # question, not answered it. Without a terminal sudo cannot prompt for a
        # password either, so the write below would most likely fail anyway and
        # leave only a confusing error behind.
        warn "No terminal to ask on: the rule is not added."
        warn "Run this installer from a terminal, or add it yourself with:"
        warn "    sudo visudo -f $SUDOERS_FILE"
        if [ "$narrow_existing" = true ]; then
            warn "Until you do, the wider rule in $OVER_BROAD_FILE is still in force:"
            warn "    sudo visudo -f $OVER_BROAD_FILE"
        fi
        return 0
    fi

    local rule_user
    rule_user="$(sudoers_rule_subject)"
    local rule_text
    rule_text="$(build_sudoers_rule "$rule_user")"

    local tmp_rule
    tmp_rule="$(mktemp /tmp/hammerspoon_wificonfig_sudoers.XXXXXX)"
    printf '%s\n' "$rule_text" > "$tmp_rule"

    # Validate the rule syntax BEFORE installing it - never break sudo.
    # Try plain visudo first, fall back to sudo visudo (may prompt once).
    if ! visudo -cf "$tmp_rule" >/dev/null 2>&1 && ! sudo visudo -cf "$tmp_rule" >/dev/null 2>&1; then
        warn "Generated sudoers rule failed validation; not applying."
        warn "Network changes will continue to prompt for a password."
        rm -f "$tmp_rule"
        return 0
    fi

    # Install it. Requires root, so sudo prompts once for the user's password.
    #
    # Never write the live drop-in in place: a cp interrupted half-way (full disk,
    # Ctrl-C) leaves a truncated file in /etc/sudoers.d, and sudo then refuses the
    # whole machine's configuration. Copy next to the destination, validate THAT
    # file, then rename - rename is atomic within a filesystem. The leading dot
    # keeps sudo from parsing the copy while it exists (sudo ignores dotted files).
    local staged
    staged="$SUDOERS_D/.hammerspoon_wificonfig.tmp.$$"
    if sudo cp "$tmp_rule" "$staged" 2>/dev/null && \
       sudo chown root:wheel "$staged" 2>/dev/null && \
       sudo chmod 0440 "$staged" 2>/dev/null && \
       sudo visudo -cf "$staged" >/dev/null 2>&1 && \
       sudo mv -f "$staged" "$SUDOERS_FILE" 2>/dev/null; then
        rm -f "$tmp_rule"
        info "Passwordless sudo rule installed: $SUDOERS_FILE"
        info "It covers only: $SUBCOMMANDS"
        info "Granted to: $rule_user"
        verify_sudoers_rule "$rule_user"

        # Only after the new rule is proven, so the machine is never left with no
        # usable grant at all: if the probe above failed, the old rule is kept and
        # only reported, because deleting it would break network switching outright
        # (io.popen gives sudo no terminal, so a prompt there just fails).
        if [ "$SUDOERS_EFFECTIVE" = true ]; then
            remove_over_broad_sudoers
        else
            warn "Not removing any older rule yet: the new one is not verified."
            warn "Once it works, drop the wider file(s) shown above so that permission"
            warn "does not stay granted after this module is gone."
        fi
    else
        sudo rm -f "$staged" 2>/dev/null || true
        rm -f "$tmp_rule"
        warn "Could not write $SUDOERS_FILE (need root)."
        warn "Run manually as admin:  sudo visudo -f $SUDOERS_FILE"
        warn "then paste:"
        warn "$rule_text"
    fi
}

# Prove the freshly written rule is actually in effect for the account that will
# use it. `sudo -n` fails when no rule covers the command, so a clean probe means
# network switches really will run silently - not merely that a file was written.
verify_sudoers_rule() {
    local rule_user="${1:-$(whoami)}"

    # Drop any cached credential: with a live ticket `sudo -n` succeeds whether or
    # not the rule covers the command, which would make this probe meaningless.
    sudo -k >/dev/null 2>&1 || true

    if passwordless_probe; then
        SUDOERS_EFFECTIVE=true
        info "Verified: '$rule_user' can run these networksetup calls without a password."
    else
        SUDOERS_EFFECTIVE=false
        warn "Rule written for '$rule_user', but a passwordless probe still fails."
        warn "Check the syntax:  sudo visudo -cf $SUDOERS_FILE"
        warn "and that the account name is the one Hammerspoon runs as: $rule_user"
    fi
}

# ============================================================================
# Detect offline / local package install
#   When this script is run from inside an extracted release archive (src/ sits
#   next to scripts/), install directly from the bundled files WITHOUT touching
#   the network. Otherwise (curl | bash) fall back to download_project().
# ============================================================================
detect_local_package() {
    local script_path="${BASH_SOURCE[0]:-$0}"
    local script_dir
    script_dir="$(cd "$(dirname "$script_path")" 2>/dev/null && pwd)"
    local pkg_root="$script_dir/.."
    if [ -d "$pkg_root/src" ] && [ -f "$pkg_root/src/init.lua" ]; then
        SRC_DIR="$pkg_root"
        TMP_DIR="$(mktemp -d)"
        LOCAL_PACKAGE=true
        return 0
    fi
    LOCAL_PACKAGE=false
    return 1
}

# ============================================================================
# Step 4: Download project files
# ============================================================================
download_project() {
    TMP_DIR=$(mktemp -d)
    local tarball_url ref tarball archive_root candidate

    # Default to the matching release tag; --branch overrides this.
    if [ "$GITHUB_BRANCH" = "main" ]; then
        ref="v${MODULE_VERSION}"
    else
        ref="refs/heads/${GITHUB_BRANCH}"
    fi

    tarball_url=$(github_url "https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/${ref}.tar.gz")
    step "Downloading project from GitHub (${ref})..."
    if [ -n "$GITHUB_PROXY" ]; then
        info "Using proxy: $GITHUB_PROXY"
    fi

    # The archive is downloaded to a file and checked before it is extracted: piped
    # straight into tar, a curl that failed (404 on a tag that was never pushed, a
    # proxy that answered with an HTML error page) would leave only tar's own
    # complaint about the archive format to explain what went wrong.
    tarball="$TMP_DIR/download.tar.gz"
    if ! curl -fsSL --retry 2 -o "$tarball" "$tarball_url"; then
        error "Failed to download project files from GitHub."
        error "URL: $tarball_url"
        exit 1
    fi

    if [ ! -s "$tarball" ] || ! tar tzf "$tarball" >/dev/null 2>&1; then
        error "Downloaded file is not a readable tar.gz archive."
        error "URL: $tarball_url"
        error "Size: $(wc -c < "$tarball" | tr -d ' ') bytes"
        exit 1
    fi

    if ! verify_tarball "$tarball" "$ref"; then
        error "Aborting: the downloaded archive failed integrity verification."
        exit 1
    fi

    if ! tar xzf "$tarball" -C "$TMP_DIR"; then
        error "Failed to extract the downloaded archive."
        exit 1
    fi
    rm -f "$tarball"

    # GitHub names the extracted directory after the ref, but a tag archive drops the
    # leading "v" (tag v3.2.1 extracts to ${GITHUB_REPO}-3.2.1) while a branch archive
    # keeps it (${GITHUB_REPO}-main), so the directory is looked up, not guessed.
    archive_root=""
    for candidate in "$TMP_DIR/${GITHUB_REPO}"*/; do
        if [ -d "$candidate" ]; then
            archive_root="${candidate%/}"
            break
        fi
    done

    if [ -z "$archive_root" ] || [ ! -f "$archive_root/scripts/install.sh" ]; then
        error "Downloaded archive structure unexpected."
        ls -la "$TMP_DIR"
        exit 1
    fi

    SRC_DIR="$archive_root"

    info "Project files downloaded ($(basename "$SRC_DIR"))."
}

# ============================================================================
# Step 5: Install / Update files
# ============================================================================
install_files() {
    local is_update="$1"
    step "Installing files to $INSTALL_DIR..."

    mkdir -p "$INSTALL_DIR/ui/templates" "$INSTALL_DIR/ui/icons"

    # Always preserve the user's config.json - fresh install, update and
    # reinstall all go through the same path.
    local preserved_config="$TMP_DIR/config.json.preserved"
    local had_config=false
    if [ -f "$INSTALL_DIR/config.json" ]; then
        cp "$INSTALL_DIR/config.json" "$preserved_config"
        had_config=true
        info "Existing config.json found - it will be preserved."
    fi

    # Copy code files (lua + ui)
    cp "$SRC_DIR/src/"*.lua "$INSTALL_DIR/"
    cp "$SRC_DIR/src/ui/"*.lua "$INSTALL_DIR/ui/"
    cp "$SRC_DIR/src/ui/templates/"* "$INSTALL_DIR/ui/templates/"
    cp "$SRC_DIR/src/ui/icons/"* "$INSTALL_DIR/ui/icons/"

    if [ "$had_config" = true ]; then
        cp "$preserved_config" "$INSTALL_DIR/config.json"
        cp "$preserved_config" "$INSTALL_DIR/config.json.backup"
        info "config.json preserved (a copy is kept as config.json.backup)."
    elif [ -f "$SRC_DIR/config.example.json" ]; then
        cp "$SRC_DIR/config.example.json" "$INSTALL_DIR/config.json"
        info "Created config.json from example template."
    fi
}

# ============================================================================
# Step 6: Inject require line into ~/.hammerspoon/init.lua
# ============================================================================
inject_require() {
    step "Configuring ~/.hammerspoon/init.lua..."

    mkdir -p "$HAMMERSPOON_DIR"

    if [ ! -f "$HAMMERSPOON_INIT" ]; then
        cat > "$HAMMERSPOON_INIT" << EOF
-- ~/.hammerspoon/init.lua

$REQUIRE_COMMENT
$REQUIRE_LINE
EOF
        info "Created ~/.hammerspoon/init.lua with wifi_autoconfig module."
        return 0
    fi

    if grep -qE "$REQUIRE_PATTERN" "$HAMMERSPOON_INIT" 2>/dev/null; then
        info "Module already required in init.lua. Skipping."
    else
        cat >> "$HAMMERSPOON_INIT" << EOF

$REQUIRE_COMMENT
$REQUIRE_LINE
EOF
        info "Added wifi_autoconfig module to init.lua."
    fi
}

# ============================================================================
# Step 7: Reload Hammerspoon
# ============================================================================
reload_hammerspoon() {
    step "Reloading Hammerspoon configuration..."

    local log="$INSTALL_DIR/wifi_autoconfig.log"
    local before=0
    if [ -f "$log" ]; then
        before="$(grep -c "" "$log" 2>/dev/null || true)"
        [ -n "$before" ] || before=0
    fi

    if pgrep -x Hammerspoon > /dev/null 2>&1; then
        if ! osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' 2>/dev/null && \
           ! osascript -e 'tell application "Hammerspoon" to reload' 2>/dev/null; then
            warn "Hammerspoon is running but refused the reload command."
            warn "Trigger it by hand: its menu bar icon -> Reload Config."
            return 0
        fi

        # The module logs a line while starting up, so a growing log is evidence it
        # actually loaded - "reload sent" on its own proves nothing.
        info "Reload requested; waiting for the module to start..."
        local waited=0
        while [ "$waited" -lt 12 ]; do
            local now=0
            if [ -f "$log" ]; then
                now="$(grep -c "" "$log" 2>/dev/null || true)"
                [ -n "$now" ] || now=0
            fi
            if [ "$now" -gt "$before" ]; then
                info "Module loaded (its log grew by $((now - before)) lines)."
                return 0
            fi
            sleep 1
            waited=$((waited + 1))
        done
        warn "Reload was sent but nothing new appeared in $log."
        warn "If the menu bar shows no Wi-Fi item, open Hammerspoon's console and reload."
    else
        open "$HAMMERSPOON_APP"
        info "Hammerspoon launched."
    fi
}

# ============================================================================
# Print success banner
# ============================================================================
print_success() {
    local is_update="$1"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    if [ "$is_update" = "true" ]; then
        echo -e "${GREEN}  Wi-Fi AutoConfig for Hammerspoon UPDATED!${NC}"
    else
        echo -e "${GREEN}  Wi-Fi AutoConfig for Hammerspoon INSTALLED!${NC}"
    fi
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "  Install location: $INSTALL_DIR"
    echo "  Config file:      $INSTALL_DIR/config.json"
    echo "  Log file:         $INSTALL_DIR/wifi_autoconfig.log"
    local silent
    if [ "$SUDOERS_EFFECTIVE" = true ]; then
        silent="enabled, probe-verified for '$(sudoers_rule_subject)' ($SUDOERS_FILE)"
    elif [ -f "$SUDOERS_FILE" ]; then
        silent="rule file present but NOT verified passwordless - switches will fail, not prompt"
    else
        silent="not enabled - the module cannot prompt, so network changes will fail"
    fi
    echo "  Silent network changes: $silent"
    if [ -n "$RESIDUAL_WIDE_FILES" ]; then
        echo "  Still wider than this module needs:$RESIDUAL_WIDE_FILES"
        echo "    Not removed because this installer did not write them (or could not)."
        echo "    Narrow or delete them yourself, e.g.: sudo visudo -f <file>"
    fi
    echo ""
    echo "  Next steps:"
    echo "    1. Click the 🌐 icon in your menu bar"
    echo "    2. Select 'Open Settings' to configure your networks"
    echo "    3. Add your Wi-Fi networks with static IP or DHCP settings"
    echo ""
    echo "  Uninstall: bash uninstall.sh"
    echo "  Update:    bash install.sh --update"
    echo ""
}

# ============================================================================
# Main
# ============================================================================
main() {
    local mode="install"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --update|-u)
                mode="update"
                shift
                ;;
            --force|-f)
                mode="force"
                shift
                ;;
            --proxy)
                if [ -n "$2" ]; then
                    GITHUB_PROXY="$2"
                    # Ensure trailing slash
                    [[ "$GITHUB_PROXY" != */ ]] && GITHUB_PROXY="${GITHUB_PROXY}/"
                    shift 2
                else
                    error "--proxy requires a URL argument"
                    exit 1
                fi
                ;;
            --branch)
                if [ -n "$2" ]; then
                    GITHUB_BRANCH="$2"
                    shift 2
                else
                    error "--branch requires an argument"
                    exit 1
                fi
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo ""
    echo -e "${BLUE}  Wi-Fi AutoConfig for Hammerspoon v${MODULE_VERSION}${NC}"
    echo -e "${BLUE}  ========================${NC}"
    echo ""

    check_os

    # Choose a download source only when the user has not supplied one explicitly
    # (GITHUB_PROXY env var or --proxy flag). This keeps the script's behaviour
    # predictable when a mirror is forced, and enables the auto speed test otherwise.
    if [ -z "$GITHUB_PROXY" ]; then
        select_mirror
    fi

    ensure_hammerspoon
    ensure_hammerspoon_dir

    if detect_local_package; then
        info "Local package detected - installing from bundled files (offline)."
    else
        download_project
    fi

    if [ "$mode" = "update" ]; then
        install_files "true"
    else
        # Check if already installed (skip for --force)
        if [ "$mode" != "force" ] && [ -f "$INSTALL_DIR/init.lua" ] && [ -f "$INSTALL_DIR/config.json" ]; then
            warn "Existing installation detected at $INSTALL_DIR"
            warn "Use --update to update code without losing config."
            echo ""
            if ask_line "Overwrite existing installation? (y/N) "; then
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    info "Aborted. Use --update to safely update."
                    exit 0
                fi
            else
                info "Non-interactive mode (curl|bash). Aborting to protect existing config."
                info "To update: bash install.sh --update"
                info "To overwrite: bash install.sh --force"
                exit 0
            fi
        fi
        install_files "false"
    fi

    inject_require

    # The passwordless rule is written last, on purpose. It grants root-level
    # networksetup calls without a password, and the download step above can fail
    # and exit - doing it first left that grant installed on a machine with no
    # module to use it, which uninstall.sh then refuses to find ("nothing to
    # uninstall") and the rule outlives everything.
    ensure_sudoers_rule

    reload_hammerspoon
    print_success "$([ "$mode" = "update" ] && echo true || echo false)"
}

main "$@"
