#!/bin/bash
#
# legacy-uninstall.sh - Completely remove a PRE-1.0 installation
#
# WHO IS THIS FOR?
#   Users who installed an older release of this project and do NOT want to
#   upgrade to v3.0.0 - they just want the old module gone. Back then the module
#   lived under one of these directories (with the old name):
#     ~/.hammerspoon/wifi_ip_switcher
#     ~/.hammerspoon/wifi_ip_controller
#
# WHAT IT DOES
#   - Backs up your old config.json to ~/.wifi_autoconfig_backups/ (override with
#     the BACKUP_DIR environment variable).
#   - Removes the old module directory.
#   - Removes the old `require(...)` line and its comment from init.lua.
#   - Reloads Hammerspoon so the change takes effect.
#
# Note: if you intend to install v3.0.0 instead, use legacy-install.sh which
# cleans the old version and then installs v3.0.0 in one step. This script
# only removes the old version.
#
# Usage:
#   bash legacy-uninstall.sh            Interactive (prompts before removal)
#   bash legacy-uninstall.sh --force    Skip prompts
#   bash legacy-uninstall.sh --help     Show help
#
set -e

# ============================================================================
# Configuration
# ============================================================================
HAMMERSPOON_DIR="$HOME/.hammerspoon"
HAMMERSPOON_INIT="$HAMMERSPOON_DIR/init.lua"

# Earlier releases shipped under one of these directory names.
LEGACY_DIRS=(
    "$HAMMERSPOON_DIR/wifi_ip_switcher"
    "$HAMMERSPOON_DIR/wifi_ip_controller"
)
BACKUP_DIR="${BACKUP_DIR:-$HOME/.wifi_autoconfig_backups}"

# Matches the old module names and their injected comment lines.
# NOTE: deliberately scoped to the exact old identifiers. The bare pattern
# "IP Switcher" was intentionally NOT included because it could match
# unrelated tools a user might have in init.lua (e.g. "VPN IP Switcher").
LEGACY_LINE_PATTERN='wifi_ip_switcher|wifi_ip_controller|Wi-Fi IP Switcher|WiFi IP Switcher'

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

show_help() {
    cat <<'EOF'
legacy-uninstall.sh - Fully remove a pre-1.0 installation

This script removes an OLDER release of this project
(~/.hammerspoon/wifi_ip_switcher or ~/.hammerspoon/wifi_ip_controller),
backs your config.json up to the Desktop, and cleans the init.lua reference.

Usage:
  bash legacy-uninstall.sh            Interactive
  bash legacy-uninstall.sh --force    Skip prompts
  bash legacy-uninstall.sh --help     Show this help
EOF
}

# ============================================================================
# Backup every legacy config.json found
# ============================================================================
backup_legacy_configs() {
    local count=0
    mkdir -p "$BACKUP_DIR"
    for dir in "${LEGACY_DIRS[@]}"; do
        if [ -f "$dir/config.json" ]; then
            local base
            base=$(basename "$dir")
            local backup="$BACKUP_DIR/wifi_autoconfig_legacy_${base}_config_backup.json"
            cp "$dir/config.json" "$backup"
            info "Backed up legacy config ($base) -> $backup"
            count=$((count + 1))
        fi
    done
    if [ "$count" -eq 0 ]; then
        warn "No legacy config.json found - nothing to back up."
    fi
}

# ============================================================================
# Remove legacy module directories
# ============================================================================
remove_legacy_dirs() {
    local removed=false
    for dir in "${LEGACY_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            step "Removing $dir..."
            rm -rf "$dir"
            info "Removed: $dir"
            removed=true
        fi
    done
    if [ "$removed" = false ]; then
        info "No legacy module directory found."
    fi
}

# ============================================================================
# Remove legacy require line / comment from init.lua
# ============================================================================
purge_legacy_require() {
    if [ ! -f "$HAMMERSPOON_INIT" ]; then
        return 0
    fi

    if ! grep -qiE "$LEGACY_LINE_PATTERN" "$HAMMERSPOON_INIT" 2>/dev/null; then
        info "No legacy reference found in init.lua."
        return 0
    fi

    step "Removing legacy reference from ~/.hammerspoon/init.lua..."
    local tmp_file
    tmp_file=$(mktemp)
    grep -viE "$LEGACY_LINE_PATTERN" "$HAMMERSPOON_INIT" > "$tmp_file" 2>/dev/null || true
    mv "$tmp_file" "$HAMMERSPOON_INIT"
    info "Removed legacy reference from init.lua."
}

# ============================================================================
# Reload Hammerspoon
# ============================================================================
reload_hammerspoon() {
    if pgrep -x Hammerspoon > /dev/null 2>&1; then
        step "Reloading Hammerspoon..."
        osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' 2>/dev/null || \
        osascript -e 'tell application "Hammerspoon" to reload' 2>/dev/null || true
        info "Hammerspoon config reloaded."
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                shift
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
    echo -e "${YELLOW}  Wi-Fi AutoConfig for Hammerspoon - legacy uninstall${NC}"
    echo -e "${YELLOW}  ==============================================${NC}"
    echo ""

    local has_legacy=false
    for dir in "${LEGACY_DIRS[@]}"; do
        [ -d "$dir" ] && has_legacy=true
    done
    if grep -qiE "$LEGACY_LINE_PATTERN" "$HAMMERSPOON_INIT" 2>/dev/null; then
        has_legacy=true
    fi

    if [ "$has_legacy" = false ]; then
        warn "No pre-1.0 installation detected. Nothing to do."
        exit 0
    fi

    if [ "$force" != true ]; then
        echo "This will completely remove the OLD module directory and its init.lua"
        echo "reference. Your old config.json will be backed up to the Desktop first."
        echo ""
        read -p "Confirm uninstall of the legacy version? (y/N) " -r || true
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Aborted."
            exit 0
        fi
    fi

    backup_legacy_configs
    remove_legacy_dirs
    purge_legacy_require
    reload_hammerspoon

    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  Legacy installation UNINSTALLED${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo ""
    echo "  Legacy config backups (if any): $BACKUP_DIR/wifi_autoconfig_legacy_*_config_backup.json"
    echo "  Hammerspoon itself was NOT removed."
    echo ""
}

main "$@"
