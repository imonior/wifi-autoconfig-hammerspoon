#!/bin/bash
#
# uninstall.sh - Uninstaller for Wi-Fi AutoConfig for Hammerspoon
#
# Usage:
#   bash uninstall.sh              Interactive uninstall (prompts for config backup)
#   bash uninstall.sh --force      Skip prompts, backup config to Desktop
#   bash uninstall.sh --help       Show help
#
set -e

# ============================================================================
# Configuration
# ============================================================================
HAMMERSPOON_DIR="$HOME/.hammerspoon"
HAMMERSPOON_INIT="$HAMMERSPOON_DIR/init.lua"
INSTALL_DIR="$HAMMERSPOON_DIR/wifi_autoconfig"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.wifi_autoconfig_backups}"
DESKTOP_BACKUP="$BACKUP_DIR/wifi_autoconfig_config_backup.json"
MODULE_VERSION="3.0.0"

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
Wi-Fi AutoConfig for Hammerspoon uninstaller

Usage:
  bash uninstall.sh              Interactive uninstall
  bash uninstall.sh --force      Skip prompts, auto-backup config to ~/.wifi_autoconfig_backups/
  bash uninstall.sh --help       Show this help message
EOF
}

# ============================================================================
# Backup config.json to ~/.wifi_autoconfig_backups/
# ============================================================================
backup_config() {
    if [ -f "$INSTALL_DIR/config.json" ]; then
        mkdir -p "$BACKUP_DIR"
        cp "$INSTALL_DIR/config.json" "$DESKTOP_BACKUP"
        info "Config backed up to: $DESKTOP_BACKUP"
    fi
}

# ============================================================================
# Remove module directory
# ============================================================================
remove_module() {
    if [ ! -d "$INSTALL_DIR" ]; then
        warn "Module directory not found: $INSTALL_DIR"
        return 0
    fi

    step "Removing $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
    info "Module files removed."
}

# ============================================================================
# Clean init.lua (remove require line)
# ============================================================================
clean_init_lua() {
    if [ ! -f "$HAMMERSPOON_INIT" ]; then
        return 0
    fi

    # Matches both the module name and the human-readable comment line we inject,
    # so no dangling comment is left behind.
    local pattern='wifi_autoconfig|Wi-Fi AutoConfig'

    if ! grep -qiE "$pattern" "$HAMMERSPOON_INIT" 2>/dev/null; then
        info "No module reference found in init.lua."
        return 0
    fi

    step "Cleaning ~/.hammerspoon/init.lua..."

    local tmp_file=$(mktemp)
    grep -viE "$pattern" "$HAMMERSPOON_INIT" > "$tmp_file" 2>/dev/null || true

    # Leave the file in place even if only comments remain (don't break other modules)
    mv "$tmp_file" "$HAMMERSPOON_INIT"
    info "Removed module references from init.lua."
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
    echo -e "${YELLOW}  Wi-Fi AutoConfig for Hammerspoon v${MODULE_VERSION} uninstaller${NC}"
    echo -e "${YELLOW}  =====================================${NC}"
    echo ""

    if [ ! -d "$INSTALL_DIR" ]; then
        warn "Module not installed at $INSTALL_DIR"
        warn "Nothing to uninstall."
        exit 0
    fi

    # Prompt for config backup
    if [ "$force" = "true" ]; then
        backup_config
    else
        if [ -f "$INSTALL_DIR/config.json" ]; then
            read -p "Backup config.json to Desktop before uninstalling? (Y/n) " -r || true
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                backup_config
            else
                warn "config.json will be deleted with the module."
            fi
        fi

        echo ""
        read -p "Confirm uninstall Wi-Fi AutoConfig for Hammerspoon? (y/N) " -r || true
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Uninstall cancelled."
            exit 0
        fi
    fi

    remove_module
    clean_init_lua
    reload_hammerspoon

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Wi-Fi AutoConfig for Hammerspoon UNINSTALLED${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    if [ -f "$DESKTOP_BACKUP" ]; then
        echo "  Config backup: $DESKTOP_BACKUP"
    fi
    echo "  Hammerspoon itself was NOT removed."
    echo "  To reinstall: bash install.sh"
    echo ""
}

main "$@"
