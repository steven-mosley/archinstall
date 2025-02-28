#!/bin/bash
#===========================================================
# Arch Linux Installation Script (Public Edition v0.1.0)
# - Usage: sudo ./install.sh [options]
# - Options: --shell=SHELL, --locale=LOCALE, --timezone=TZ, --debug, --unsupported-boot-media, --check-version, --skip-boot-check
#===========================================================

set -u
[[ $EUID -ne 0 ]] && { echo "Run as root."; exit 1; }

# Constants
VERSION="0.1.0"
BASE_DIR="$(dirname "$(realpath "$0")")"
LOG_FILE="/var/log/archinstall.log"
DEBUG=0
UNSUPPORTED=0
SKIP_BOOT_CHECK=0
CHECK_VERSION=0
REPO_URL="https://raw.githubusercontent.com/YOUR_USERNAME/archinstall/main"  # Replace with your GitHub repo

# Source modules
for module in "$BASE_DIR"/modules/*.sh; do
    source "$module" || { echo "Failed to load $module"; exit 1; }
done

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --shell=*) DEFAULT_SHELL="${1#*=}" ;;
            --locale=*) DEFAULT_LOCALE="${1#*=}" ;;
            --timezone=*) DEFAULT_TZ="${1#*=}" ;;
            --debug) DEBUG=1 ;;
            --unsupported-boot-media) UNSUPPORTED=1 ;;
            --check-version) CHECK_VERSION=1 ;;
            --skip-boot-check) SKIP_BOOT_CHECK=1 ;;
            --version) echo "Archinstall v$VERSION"; exit 0 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
        shift
    done
}

check_version() {
    log "Checking for updates..."
    local remote_version
    remote_version=$(curl -s "$REPO_URL/VERSION" 2>/dev/null)
    if [[ -z "$remote_version" || ! "$remote_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "${YELLOW}Couldn’t fetch a valid version (offline or repo not set up?). Running v$VERSION.${NC}"
        return 0
    fi
    if [[ "$remote_version" != "$VERSION" ]]; then
        log "${YELLOW}New version available: v$remote_version (you’re on v$VERSION).${NC}"
        prompt "Update recommended. Continue with current version? (y/n): " continue
        [[ "$continue" =~ ^[Yy] ]] || { log "Please update from $REPO_URL"; exit 1; }
    else
        log "You’re running the latest version (v$VERSION)."
    fi
}

main() {
    clear > /dev/tty
    parse_args "$@"
    log "Starting Arch Linux installation (v$VERSION)..."
    [[ $CHECK_VERSION -eq 1 ]] && check_version
    [[ $SKIP_BOOT_CHECK -eq 0 ]] && check_boot_media
    check_internet
    check_uefi
    optimize_mirrors
    create_disk_menu
    verify_disk_space "$selected_disk" || exit 1
    wipe_partitions
    create_partition_menu
    perform_partitioning "$selected_disk" "$partition_choice"
    install_base_system || exit 1
    setup_network
    configure_system
    setup_user_accounts || exit 1
    cleanup
    log "Installation complete! Reboot to start your new system."
}

main "$@"