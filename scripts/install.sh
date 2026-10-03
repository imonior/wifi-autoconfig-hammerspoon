#!/bin/bash
#
# install.sh - One-command installer for Wi-Fi AutoConfig for Hammerspoon
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash
#   curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash  # China mirror
#   bash install.sh              # Fresh install
#   bash install.sh --update     # Update code only (preserves config.json)
#   bash install.sh --proxy URL  # Use GitHub proxy
#   bash install.sh --help       # Show help
#
set -e

# ============================================================================
# Configuration
# ============================================================================
GITHUB_USER="imonior"
GITHUB_REPO="wifi-autoconfig-hammerspoon"
GITHUB_BRANCH="main"
MODULE_VERSION="3.2.0"

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

# Matches both the module name and the human-readable comment line we inject,
# so no dangling comment is left behind after an upgrade or an uninstall.
INIT_LINE_PATTERN='wifi_autoconfig|Wi-Fi AutoConfig'

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

show_help() {
    cat <<'EOF'
Wi-Fi AutoConfig for Hammerspoon installer

Usage:
  bash install.sh              Fresh install (installs Hammerspoon if missing)
  bash install.sh --update     Update code only, preserves your config.json
  bash install.sh --force      Overwrite existing installation without prompting
  bash install.sh --proxy URL  Use GitHub proxy (for faster access in China)
  bash install.sh --help       Show this help message

One-liner (curl | bash):
  curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash

  With proxy (for China):
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash

  With update:
  curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash -s -- --update

  With proxy + update:
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash -s -- --update

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
#   (On the maintainer's machine this rule already lives in
#    /etc/sudoers.d/hammerspoon_network and is detected as "already configured".)
# ============================================================================
SUDOERS_FILE="/etc/sudoers.d/hammerspoon_netconfig"

ensure_sudoers_rule() {
    step "Checking passwordless sudo for network changes..."

    # Already passwordless? (real machine; the Bash sandbox test is irrelevant)
    if sudo -n /usr/sbin/networksetup -listallnetworkservices >/dev/null 2>&1; then
        info "Passwordless sudo already configured. Skipping."
        return 0
    fi

    warn "Network changes currently require a password on every switch."
    warn "This installer can add a passwordless sudoers rule so it stays silent."
    echo ""
    if [ -t 0 ]; then
        read -p "Add passwordless sudo rule for networksetup now? (y/N) " -r || true
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            warn "Skipped. You can add it later or enter your password each time."
            return 0
        fi
    else
        info "Non-interactive mode: attempting to add the rule (you may be prompted once)."
    fi

    local rule_user
    rule_user="$(whoami)"
    local rule_text
    rule_text="# Wi-Fi AutoConfig for Hammerspoon
# Allows passwordless network configuration changes (IP / DNS / DHCP / IPv6).
# Generated by install.sh on $(date)
${rule_user} ALL=(ALL) NOPASSWD: /usr/sbin/networksetup"

    local tmp_rule
    tmp_rule="$(mktemp /tmp/hammerspoon_netconfig_sudoers.XXXXXX)"
    printf '%s\n' "$rule_text" > "$tmp_rule"

    # Validate the rule syntax BEFORE installing it - never break sudo.
    # Try plain visudo first, fall back to sudo visudo (may prompt once).
    if ! visudo -cf "$tmp_rule" >/dev/null 2>&1 && ! sudo visudo -cf "$tmp_rule" >/dev/null 2>&1; then
        warn "Generated sudoers rule failed validation; not applying."
        warn "Network changes will continue to prompt for a password."
        rm -f "$tmp_rule"
        return 0
    fi

    # Write it. Requires root, so sudo prompts once for the user's password.
    if sudo cp "$tmp_rule" "$SUDOERS_FILE" 2>/dev/null && \
       sudo chown root:wheel "$SUDOERS_FILE" 2>/dev/null && \
       sudo chmod 0440 "$SUDOERS_FILE" 2>/dev/null; then
        rm -f "$tmp_rule"
        info "Passwordless sudo rule installed: $SUDOERS_FILE"
        info "Network changes will now run silently (no password prompt)."
    else
        warn "Could not write $SUDOERS_FILE (need root)."
        warn "Run manually as admin:  sudo visudo -f $SUDOERS_FILE"
        warn "then paste:  ${rule_user} ALL=(ALL) NOPASSWD: /usr/sbin/networksetup"
        rm -f "$tmp_rule"
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
    local tarball_url
    tarball_url=$(github_url "https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.tar.gz")
    step "Downloading project from GitHub..."
    if [ -n "$GITHUB_PROXY" ]; then
        info "Using proxy: $GITHUB_PROXY"
    fi

    if ! curl -fsSL "$tarball_url" | tar xz -C "$TMP_DIR" 2>/dev/null; then
        error "Failed to download project files from GitHub."
        error "URL: $tarball_url"
        exit 1
    fi

    SRC_DIR="$TMP_DIR/${GITHUB_REPO}-${GITHUB_BRANCH}"

    if [ ! -d "$SRC_DIR" ]; then
        error "Downloaded archive structure unexpected."
        ls -la "$TMP_DIR"
        exit 1
    fi

    info "Project files downloaded."
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

    if grep -qF 'wifi_autoconfig' "$HAMMERSPOON_INIT" 2>/dev/null; then
        info "Module already referenced in init.lua. Skipping."
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

    if pgrep -x Hammerspoon > /dev/null 2>&1; then
        osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' 2>/dev/null || \
        osascript -e 'tell application "Hammerspoon" to reload' 2>/dev/null || true
        info "Hammerspoon config reloaded."
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
    echo "  Silent network changes: $([ -f "$SUDOERS_FILE" ] && echo "enabled ($SUDOERS_FILE)" || echo "not enabled - sudo will prompt")"
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
    ensure_hammerspoon
    ensure_hammerspoon_dir
    ensure_sudoers_rule

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
            if [ -t 0 ]; then
                read -p "Overwrite existing installation? (y/N) " -r || true
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
    reload_hammerspoon
    print_success "$([ "$mode" = "update" ] && echo true || echo false)"
}

main "$@"
