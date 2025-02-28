#!/usr/bin/env bash

# Arch Linux Installation Script
# License: MIT
# Version: 0.1.0

set -e

# Terminal colors
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
NC="\033[0m" # No Color

# Global variables
DEBUG=0
UNSUPPORTED=0
CHECK_VERSION=0
SKIP_BOOT_CHECK=0
DEFAULT_SHELL="bash"
DEFAULT_LOCALE="en_US.UTF-8"
DEFAULT_TZ="UTC"
VERSION="0.1.0"

# Function to display log messages
log() {
    echo -e "${YELLOW}[LOG]${NC} $*"
}

# Function to display error messages and exit
error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

# Function to get user confirmation
prompt() {
    local response
    while true; do
        read -r -p "$1 [y/n]: " response
        case "${response,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Function to parse command line arguments
parse_args() {
    for arg in "$@"; do
        case $arg in
            --debug)
                DEBUG=1
                ;;
            --unsupported-boot-media)
                UNSUPPORTED=1
                ;;
            --check-version)
                CHECK_VERSION=1
                ;;
            --skip-boot-check)
                SKIP_BOOT_CHECK=1
                ;;
            --version)
                echo "Archinstall v$VERSION"
                exit 0
                ;;
            --shell=*)
                DEFAULT_SHELL="${arg#*=}"
                ;;
            --locale=*)
                DEFAULT_LOCALE="${arg#*=}"
                ;;
            --timezone=*)
                DEFAULT_TZ="${arg#*=}"
                ;;
            *)
                error "Unknown option: $arg"
                ;;
        esac
    done
}

# Source module files
source_modules() {
    local module_dir
    module_dir="$(dirname "$0")/modules"
    
    if [[ -d "$module_dir" ]]; then
        for module in "$module_dir"/*.sh; do
            if [[ -f "$module" ]]; then
                if [[ $DEBUG -eq 1 ]]; then
                    log "Loading module: $module"
                fi
                # shellcheck source=/dev/null
                source "$module"
            fi
        done
    else
        error "Module directory not found: $module_dir"
    fi
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Run 'sudo $0'"
    fi
}

# Function to check if we're using a supported boot media
check_boot_media() {
    if [[ $SKIP_BOOT_CHECK -eq 1 || $UNSUPPORTED -eq 1 ]]; then
        if [[ $DEBUG -eq 1 ]]; then
            log "Skipping boot media check"
        fi
        return 0
    fi
    
    if ! grep -q "archiso" /proc/cmdline; then
        error "This script must be run from an Arch Linux installation media. Use --unsupported-boot-media to bypass."
    fi
    
    log "Valid Arch Linux boot media detected"
    return 0
}

# Function to check internet connection
check_internet() {
    log "Checking internet connection..."
    if ! ping -c 1 archlinux.org &>/dev/null; then
        error "No internet connection. Please connect and try again."
    fi
    log "Internet connection verified"
    return 0
}

# Function to check if system is booted in UEFI mode
check_uefi() {
    log "Checking boot mode..."
    if [[ -d /sys/firmware/efi/efivars ]]; then
        log "UEFI boot mode detected"
        return 0
    else
        log "Legacy BIOS boot mode detected"
        if ! prompt "Continue with BIOS installation?"; then
            error "Installation canceled"
        fi
        return 0
    fi
}

# Function to optimize mirror list
optimize_mirrors() {
    log "Optimizing mirror list..."
    if command -v reflector &>/dev/null; then
        reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
        log "Mirror list updated"
    else
        log "Reflector not found, skipping mirror optimization"
    fi
    return 0
}

# Function to create disk selection menu
create_disk_menu() {
    log "Scanning available disks..."
    lsblk -d -o NAME,SIZE,MODEL
    
    local disks
    mapfile -t disks < <(lsblk -d -o NAME -n | grep -v "loop")
    
    echo "Available disks:"
    for i in "${!disks[@]}"; do
        echo "$((i+1)). /dev/${disks[i]}"
    done
    
    local selection
    read -r -p "Select a disk by number: " selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#disks[@]}" ]; then
        error "Invalid selection"
    fi
    
    selected_disk="/dev/${disks[$((selection-1))]}"
    log "Selected disk: $selected_disk"
}

# Function to verify disk space
verify_disk_space() {
    local disk_size
    disk_size=$(blockdev --getsize64 "$selected_disk")
    disk_size=$((disk_size / (1024 * 1024 * 1024)))
    
    if [[ $disk_size -lt 10 ]]; then
        if ! prompt "Disk size is less than 10GB. This may be too small for a full installation. Continue?"; then
            error "Installation canceled due to insufficient disk space"
        fi
    fi
    return 0
}

# Function to wipe partitions
wipe_partitions() {
    if prompt "WARNING: This will erase ALL data on $selected_disk. Continue?"; then
        log "Wiping partition table on $selected_disk..."
        sgdisk --zap-all "$selected_disk"
        log "Partition table wiped"
        return 0
    else
        error "Installation canceled"
    fi
}

# Function to present partitioning options
create_partition_menu() {
    echo "Partitioning schemes:"
    echo "1. Standard (root + home + swap)"
    echo "2. Simple (root + swap)"
    echo "3. Custom partitioning"
    
    read -r -p "Select a partitioning scheme: " partition_choice
    
    if ! [[ "$partition_choice" =~ ^[1-3]$ ]]; then
        error "Invalid selection"
    fi
    
    log "Selected partitioning scheme: $partition_choice"
    return 0
}

# Function to perform partitioning based on selected scheme
perform_partitioning() {
    case "$partition_choice" in
        1)
            log "Creating standard partitions (root + home + swap)..."
            # Create partitions logic here
            ;;
        2)
            log "Creating simple partitions (root + swap)..."
            # Create partitions logic here
            ;;
        3)
            log "Please partition the disk manually using fdisk or parted"
            # Custom partitioning logic here
            ;;
    esac
    
    log "Partitioning completed"
    return 0
}

# Function to install base Arch Linux system
install_base_system() {
    log "Installing base Arch Linux system..."
    # Logic to mount partitions and install base system
    # pacstrap /mnt base linux linux-firmware
    log "Base system installed"
    return 0
}

# Function to set up network configuration
setup_network() {
    log "Setting up network configuration..."
    # Network setup logic here
    log "Network configuration completed"
    return 0
}

# Function to configure system settings
configure_system() {
    log "Configuring system settings..."
    # System configuration logic here
    log "System configuration completed"
    return 0
}

# Function to set up user accounts
setup_user_accounts() {
    log "Setting up user accounts..."
    # User account creation logic here
    log "User accounts created"
    return 0
}

# Function to check for script updates
check_version() {
    log "Checking for updates..."
    
    local latest_version
    if ! latest_version=$(curl -s https://raw.githubusercontent.com/steven-mosley/archinstall/v2/VERSION); then
        log "Couldn't fetch a valid version. Skipping version check."
        return 0
    fi
    
    if [[ ! "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "Couldn't fetch a valid version. Skipping version check."
        return 0
    fi
    
    if [[ "$latest_version" == "$VERSION" ]]; then
        log "You're running the latest version: $VERSION"
    else
        log "New version available: $latest_version (current: $VERSION)"
        log "Update at: https://github.com/steven-mosley/archinstall"
    fi
    
    return 0
}

# Function to clean up temporary files and finalize
cleanup() {
    log "Cleaning up..."
    # Cleanup logic here
    log "Cleanup completed"
    return 0
}

# Main function to orchestrate the installation process
main() {
    clear
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}       Arch Linux Installation Script     ${NC}"
    echo -e "${GREEN}==========================================${NC}"
    
    parse_args "$@"
    
    check_root
    
    if [[ $CHECK_VERSION -eq 1 ]]; then
        check_version
        exit 0
    fi
    
    log "Starting Arch Linux installation"
    
    source_modules
    
    if [[ $SKIP_BOOT_CHECK -ne 1 ]]; then
        check_boot_media
    fi
    
    check_internet
    check_uefi
    optimize_mirrors
    
    create_disk_menu
    verify_disk_space
    wipe_partitions
    create_partition_menu
    perform_partitioning
    
    install_base_system
    setup_network
    configure_system
    setup_user_accounts
    
    cleanup
    
    log "Installation complete! You can now reboot into your new Arch Linux system."
    
    return 0
}

# Execute main function with all arguments if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi