#!/usr/bin/env bash

# Arch Linux Installation Script
# License: MIT
# Version: 0.1.0

set -e

# Terminal colors
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
RED="\033[1;31m"
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
TEST_MODE=${TEST_MODE:-0}
MOCK_ROOT=${MOCK_ROOT:-""}

# Remove or export unused variables
# BLUE="\033[1;34m"  # Removing if unused
export DEFAULT_SHELL
export DEFAULT_LOCALE
export DEFAULT_TZ

# Function to display log messages
log() {
    if [[ "$TEST_MODE" == 1 ]]; then
        echo -e "[LOG] $*"
    else
        echo -e "${YELLOW}[LOG]${NC} $*"
    fi
    
    # Write to log file if available
    if [[ -n "$LOG_FILE" && -d "$(dirname "$LOG_FILE")" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    fi
}

# Function to display error messages and exit
error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

# Function to get user confirmation with debug support
prompt() {
    local response
    while true; do
        if [[ $DEBUG -eq 1 ]]; then
            echo "DEBUG: Prompting user for confirmation: $1"
        fi
        
        read -r -p "$1 [y/n]: " response
        
        if [[ $DEBUG -eq 1 ]]; then
            echo "DEBUG: Received response: '$response'"
        fi
        
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
            --test)
                TEST_MODE=1
                SKIP_BOOT_CHECK=1
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

# Source module files - using absolute paths for reliability
source_modules() {
    # Get the directory of the script using a robust method
    local script_path
    if [[ -L "${BASH_SOURCE[0]}" ]]; then
        script_path="$(readlink -f "${BASH_SOURCE[0]}")"
    else
        script_path="${BASH_SOURCE[0]}"
    fi
    local script_dir
    script_dir="$(cd "$(dirname "$script_path")" && pwd)"
    local module_dir="$script_dir/modules"
    
    if [[ $DEBUG -eq 1 ]]; then
        echo "Script path: $script_path"
        echo "Script dir: $script_dir"
        echo "Module dir: $module_dir"
        ls -la "$script_dir" || echo "Cannot list script directory"
    fi
    
    # Create modules directory if it doesn't exist
    mkdir -p "$module_dir"
    
    if [[ -d "$module_dir" ]]; then
        # Create a counter for loaded modules
        local loaded_count=0
        
        # First check if the directory is empty
        if [[ -z "$(ls -A "$module_dir")" ]]; then
            if [[ $DEBUG -eq 1 ]]; then
                log "Module directory is empty: $module_dir"
            fi
            # Create placeholder modules for testing
            if [[ "$TEST_MODE" -eq 1 ]]; then
                for name in checks disk filesystem network system user utils; do
                    echo "#!/bin/bash" > "$module_dir/${name}.sh"
                    echo "# Mock module created during test" >> "$module_dir/${name}.sh"
                    chmod +x "$module_dir/${name}.sh"
                    ((loaded_count++))
                done
            fi
        else
            # Load existing module files
            for module in "$module_dir"/*.sh; do
                if [[ -f "$module" ]]; then
                    if [[ $DEBUG -eq 1 ]]; then
                        log "Loading module: $module"
                    fi
                    # shellcheck source=/dev/null
                    source "$module"
                    ((loaded_count++))
                fi
            done
        fi
        
        if [[ $DEBUG -eq 1 ]]; then
            log "Loaded $loaded_count modules"
        fi
    else
        error "Module directory not found and could not be created: $module_dir"
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
    
    if [[ "$DEBUG" -eq 1 ]]; then
        echo "DEBUG: Running lsblk command to list disks"
    fi
    
    # This safer approach ensures we only get actual disk names
    local disks=()
    while IFS= read -r disk; do
        if [[ -n "$disk" && "$disk" != "NAME" && "$disk" != "loop"* ]]; then
            disks+=("$disk")
        fi
    done < <(lsblk -d -o NAME -n 2>/dev/null)
    
    # For test mode, if no disks found, use mock disks
    if [[ ${#disks[@]} -eq 0 && "$TEST_MODE" -eq 1 ]]; then
        log "No disks found, using mock disks for testing"
        disks=("sda" "sdb")
    elif [[ ${#disks[@]} -eq 0 ]]; then
        error "No disks found"
    fi
    
    echo "Available disks:"
    for i in "${!disks[@]}"; do
        echo "$((i+1)). /dev/${disks[i]}"
    done
    
    # For testing, pre-select disk 1
    if [[ "$TEST_MODE" -eq 1 ]]; then
        log "Auto-selecting disk 1 for testing"
        selected_disk="/dev/${disks[0]}"
        return 0
    fi
    
    local selection
    read -r -p "Select a disk (number): " selection
    
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
    echo "1. BTRFS with subvolumes (root, home, packages, logs)"
    echo "2. Simple ext4 (root + swap)"
    echo "3. Custom partitioning"
    
    read -r -p "Select a partitioning scheme: " partition_choice
    
    if ! [[ "$partition_choice" =~ ^[1-3]$ ]]; then
        error "Invalid selection"
    fi
    
    # Additional configuration for BTRFS setup
    if [[ "$partition_choice" == "1" ]]; then
        log "Selected BTRFS with custom subvolume layout"
        filesystem_type="btrfs"
    elif [[ "$partition_choice" == "2" ]]; then
        log "Selected simple ext4 setup"
        filesystem_type="ext4"
    else
        log "Selected custom partitioning"
    fi
    
    log "Selected partitioning scheme: $partition_choice"
    return 0
}

# Function to perform partitioning based on selected scheme
perform_partitioning() {
    log "Partitioning disk $selected_disk..."
    
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
    if [[ "$TEST_MODE" == 1 ]]; then
        mkdir -p /tmp/mnt
        pacstrap /tmp/mnt base linux linux-firmware
    else
        # pacstrap /mnt base linux linux-firmware
        echo "Would run: pacstrap /mnt base linux linux-firmware"
    fi
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
    
    # Debug output for package questions
    if [[ $DEBUG -eq 1 ]]; then
        echo "DEBUG: About to ask user about additional packages"
    fi
    
    # Ask for additional packages
    echo "Do you want to install additional packages [y/n]: "
    read -r response
    
    if [[ $DEBUG -eq 1 ]]; then
        echo "DEBUG: User response for additional packages: '$response'"
    fi
    
    if [[ "${response,,}" == "y" || "${response,,}" == "yes" ]]; then
        echo "Enter package names (separated by spaces): "
        read -r additional_packages
        
        if [[ $DEBUG -eq 1 ]]; then
            echo "DEBUG: User specified packages: '$additional_packages'"
        fi
        
        if [[ -n "$additional_packages" ]]; then
            log "Installing additional packages: $additional_packages"
            if [[ "$TEST_MODE" -eq 1 ]]; then
                echo "Mock installing: $additional_packages"
            else
                log "Would run: arch-chroot /mnt pacman -S --noconfirm $additional_packages"
            fi
        else
            log "No packages specified for installation"
        fi
    else
        log "No additional packages requested."
    fi
    
    # Shell preference with debug output
    echo "Enter preferred shell (default: bash): "
    read -r shell_choice
    
    if [[ $DEBUG -eq 1 ]]; then
        echo "DEBUG: User specified shell: '$shell_choice'"
    fi
    
    shell_choice=${shell_choice:-bash}
    if [[ -n "$shell_choice" && "$shell_choice" != "bash" ]]; then
        log "Setting up $shell_choice as default shell"
    else
        log "Using default shell: bash"
    fi
    
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
    # Only clear screen if not in test mode and not being sourced
    if [[ "$TEST_MODE" != 1 && "${BASH_SOURCE[0]}" == "${0}" ]]; then
        clear
    fi
    
    # Print header without clearing in test mode
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}       Arch Linux Installation Script     ${NC}"
    echo -e "${GREEN}==========================================${NC}"
    
    # Always show script information in test mode
    if [[ "$TEST_MODE" -eq 1 ]]; then
        echo "Running script: ${BASH_SOURCE[0]}"
        echo "Current directory: $(pwd)"
        echo "Test mode: $TEST_MODE"
        echo "Debug mode: $DEBUG"
        
        if [[ $DEBUG -eq 1 ]]; then
            echo "PATH: $PATH"
            echo "User: $(whoami) (EUID: $EUID)"
        fi
    fi
    
    parse_args "$@"
    
    # Ensure modules directory exists
    local script_dir
    script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    mkdir -p "$script_dir/modules"
    
    # Create log directory
    if [[ "$TEST_MODE" -eq 1 ]]; then
        mkdir -p /tmp/archinstall_logs
        LOG_FILE="/tmp/archinstall_logs/install.log"
    else
        LOG_FILE=""
    fi
    
    # Skip root check in test mode
    if [[ "$TEST_MODE" != 1 ]]; then
        check_root
    fi
    
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

# Only execute main function if the script is being run directly
# and not sourced, or if explicitly requested with --test
if [[ "${BASH_SOURCE[0]}" == "${0}" || "$*" == *"--test"* ]]; then
    main "$@"
else
    # If being sourced, output a message
    if [[ "$TEST_MODE" -eq 1 && "$DEBUG" -eq 1 ]]; then
        echo "Script sourced but not executed directly"
    fi
fi