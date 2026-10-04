#!/bin/bash
#
# legacy-install.sh - Upgrade a PRE-1.0 installation to the current version in one step
#
# WHO IS THIS FOR?
#   Users who previously installed an older release of this project. Back then
#   the module lived under one of these directories (with the old name):
#     ~/.hammerspoon/wifi_ip_switcher
#     ~/.hammerspoon/wifi_ip_controller
#
# WHAT IT DOES (legacy-migrate + install.sh combined)
#   1. Backs up your old config.json to ~/.wifi_autoconfig_backups/ (override with
#      the BACKUP_DIR environment variable) - no automatic migration, because
#      the 3.x line is a fresh start - you import rules manually afterwards.
#   2. Removes the old module directory.
#   3. Removes the old `require(...)` line and its comment from init.lua, so
#      Hammerspoon will not fail to load after the upgrade.
#   4. Runs the standard installer (install.sh) to install the current version cleanly.
#
# Usage:
#   bash legacy-install.sh            Interactive (prompts before cleanup)
#   bash legacy-install.sh --force    Skip the cleanup prompt
#   bash legacy-install.sh --help     Show help
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

# Is a terminal actually attached? /dev/tty keeps existing as a character device when
# nothing is behind it, and `-c /dev/tty` still says yes, so the only honest test is to
# open it. A failed redirect is reported by the shell to its own stderr, which a
# command-level 2>/dev/null cannot hide - hence the subshell.
has_tty() {
    ( exec </dev/tty ) 2>/dev/null
}

# Ask a question even when the script arrived over a pipe (curl | bash), where stdin is
# the script body: a bare `read` there consumes the next command line as the answer and
# bash carries on after it, silently skipping steps - in this script those steps delete
# directories. Returns 0 when the user was actually asked, 1 when there is nobody to ask.
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

show_help() {
    cat <<'EOF'
legacy-install.sh - Upgrade a pre-1.0 installation to the current version

This script removes an OLDER release of this project
(~/.hammerspoon/wifi_ip_switcher or ~/.hammerspoon/wifi_ip_controller),
backs your config.json up to ~/.wifi_autoconfig_backups/, cleans the init.lua reference, and
then runs install.sh to install the current version cleanly.

Usage:
  bash legacy-install.sh            Interactive (prompts before cleanup)
  bash legacy-install.sh --force    Skip the cleanup prompt
  bash legacy-install.sh --help     Show this help
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

    # Only the lines this project actually wrote: an anchored require of one of the
    # legacy module names, or a comment line that is nothing but the old display
    # name. The detection above stays loose on purpose, but a loose match must never
    # become a deletion - an unrelated line of yours that merely mentions the old
    # name (or a sentence inside a larger comment) is left alone.
    local delete_pattern='^[[:space:]]*((local[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*([[:space:]]*,[[:space:]]*[A-Za-z_][A-Za-z0-9_]*)*[[:space:]]*=[[:space:]]*)?require[^[:alnum:]_]*wifi_ip_(switcher|controller)|^[[:space:]]*--+[[:space:]]*(Wi-Fi|WiFi) IP Switcher[[:space:]]*$'

    if ! grep -qE "$delete_pattern" "$HAMMERSPOON_INIT" 2>/dev/null; then
        warn "A line mentions the legacy module, but none looks like the require line"
        warn "this project wrote, so init.lua is left untouched."
        warn "Remove it by hand if it is yours to remove: $HAMMERSPOON_INIT"
        return 0
    fi

    step "Removing legacy reference from ~/.hammerspoon/init.lua..."
    echo "The following lines will be removed:"
    grep -nE "$delete_pattern" "$HAMMERSPOON_INIT" 2>/dev/null | while IFS= read -r line; do
        echo "    | $line"
    done

    mkdir -p "$BACKUP_DIR"
    cp "$HAMMERSPOON_INIT" "$BACKUP_DIR/init.lua.before-legacy-upgrade"

    # Built beside the target and renamed over it: mktemp's file in /tmp is mode 0600,
    # and moving that onto init.lua would quietly change its permissions.
    local tmp_file="$HAMMERSPOON_INIT.legacy.tmp.$$"
    if ! cp -p "$HAMMERSPOON_INIT" "$tmp_file" 2>/dev/null; then
        error "Could not create a temporary copy beside $HAMMERSPOON_INIT; init.lua left untouched."
        return 0
    fi
    grep -vE "$delete_pattern" "$HAMMERSPOON_INIT" > "$tmp_file" 2>/dev/null || true
    mv -f "$tmp_file" "$HAMMERSPOON_INIT"
    info "Removed legacy reference from init.lua."
    info "Original init.lua backed up to: $BACKUP_DIR/init.lua.before-legacy-upgrade"
}

# ============================================================================
# Run the standard installer
# ============================================================================
run_installer() {
    local installer
    installer="$(dirname "$0")/install.sh"
    if [ -f "$installer" ]; then
        step "Launching installer (install.sh)..."
        bash "$installer"
    else
        error "install.sh not found next to this script."
        error "Please run it manually:  bash install.sh"
        exit 1
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
    echo -e "${YELLOW}  Wi-Fi AutoConfig for Hammerspoon - legacy upgrade${NC}"
    echo -e "${YELLOW}  ==============================================${NC}"
    echo ""

    local has_legacy=false
    for dir in "${LEGACY_DIRS[@]}"; do
        if [ -d "$dir" ]; then has_legacy=true; fi
    done
    if grep -qiE "$LEGACY_LINE_PATTERN" "$HAMMERSPOON_INIT" 2>/dev/null; then
        has_legacy=true
    fi

    if [ "$has_legacy" = false ]; then
        warn "No pre-1.0 installation detected - nothing to clean."
        warn "Proceeding with a fresh install..."
        run_installer
        exit 0
    fi

    if [ "$force" != true ]; then
        echo "This will remove the OLD module directory and its init.lua reference,"
        echo "back up your old config.json to ~/.wifi_autoconfig_backups/, then install the current version."
        echo ""
        if ask_line "Proceed? (y/N) "; then
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "Aborted."
                exit 0
            fi
        else
            error "Not changing anything: there was no terminal to confirm on."
            error "Run this from a terminal, or pass --force to skip the prompts."
            exit 1
        fi
    fi

    backup_legacy_configs
    remove_legacy_dirs
    purge_legacy_require

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Legacy installation cleaned up${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "  Legacy config backups (if any): $BACKUP_DIR/wifi_autoconfig_legacy_*_config_backup.json"
    echo ""

    run_installer
}

main "$@"
