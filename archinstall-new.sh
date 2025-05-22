#!/bin/bash

#===========================================================
# Arch Linux Installation Script - XDG + Zsh Everywhere
#===========================================================

readonly LOG_FILE="/var/log/archinstall.log"
readonly MIN_DISK_SIZE=$((20 * 1024 * 1024 * 1024)) # 20GB in bytes

#-----------------------------------------------------------
# Core Utilities
#-----------------------------------------------------------

init_log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
}

log() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

handle_error() {
    local exit_code=$?
    local line_number=$1
    log "ERROR on line $line_number: Command exited with status $exit_code"
    log "Installation failed. See log file at $LOG_FILE for details."
    exit $exit_code
}

prompt() {
    local message="$1"
    local varname="$2"
    echo "$message" > /dev/tty
    read -r "$varname" < /dev/tty
}

confirm_operation() {
    local message="$1"
    local response
    prompt "$message (yes/no): " response
    if [[ ! "$response" =~ ^[Yy][Ee][Ss]|[Yy]$ ]]; then
        log "Operation cancelled by user"
        return 1
    fi
    return 0
}

#-----------------------------------------------------------
# Validation Functions
#-----------------------------------------------------------

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
}

check_boot_media() {
    if [ -d /run/archiso ]; then
        return 0
    fi
    for arg in "$@"; do
        if [ "$arg" = "--unsupported-boot-media" ]; then
            log "WARNING: Unofficial boot media detected, proceeding as requested"
            return 0
        fi
    done
    log "ERROR: Unofficial boot media detected. This script requires official Arch ISO."
    log "To override, rerun with the --unsupported-boot-media flag."
    exit 1
}

check_internet() {
    log "Checking internet connectivity..."
    if ! ping -c 1 archlinux.org &>/dev/null; then
        log "ERROR: No internet connection detected"
        exit 1
    fi
    log "Internet connection verified"
}

check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        log "ERROR: System not booted in UEFI mode"
        exit 1
    fi
    log "UEFI boot mode verified"
}

verify_disk_space() {
    local disk="$1"
    if [[ ! -b "$disk" ]]; then
        log "ERROR: Disk $disk does not exist or is not a block device"
        return 1
    fi
    local disk_size
    disk_size=$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)
    if [[ "$disk_size" -eq 0 ]]; then
        disk_size=$(lsblk -b -n -o SIZE "$disk" 2>/dev/null | head -n1 || echo 0)
    fi
    local disk_model
    disk_model=$(lsblk -n -o MODEL "$disk" 2>/dev/null | tr -d ' ' || echo "")
    if [[ "$disk_model" == *"QEMU"* || "$disk_model" == *"VBOX"* ]]; then
        log "QEMU/VirtualBox disk detected: $disk. Skipping size verification."
        return 0
    fi
    if ((disk_size < MIN_DISK_SIZE)); then
        if command -v numfmt >/dev/null 2>&1; then
            log "ERROR: Disk size ($(numfmt --to=iec-i --suffix=B ${disk_size})) is too small."
            log "Minimum required: $(numfmt --to=iec-i --suffix=B ${MIN_DISK_SIZE})"
        else
            log "ERROR: Disk size (${disk_size} bytes) is too small."
            log "Minimum required: ${MIN_DISK_SIZE} bytes (approx. 20GB)"
        fi
        return 1
    fi
    if command -v numfmt >/dev/null 2>&1; then
        log "Disk size verified: $(numfmt --to=iec-i --suffix=B ${disk_size})"
    else
        log "Disk size verified: ${disk_size} bytes"
    fi
    return 0
}

#-----------------------------------------------------------
# Disk and Partition Management
# (unchanged, omitted for brevity)
#-----------------------------------------------------------
# ... [keep your previous partitioning/disk functions unchanged] ...

#-----------------------------------------------------------
# SYSTEM INSTALLATION
#-----------------------------------------------------------

select_install_packages() {
    install_pkgs=(base linux linux-firmware sudo grub efibootmgr networkmanager)
    microcode_pkg=""
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        microcode_pkg="intel-ucode"
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        microcode_pkg="amd-ucode"
    fi
    prompt "Do you want to use zsh as your default shell? (yes/no): " use_zsh
    if [[ "$use_zsh" =~ ^[Yy][Ee][Ss]|[Yy]$ ]]; then
        default_shell="zsh"
        install_pkgs+=("zsh")
    else
        default_shell="bash"
    fi
    if [[ "$partition_choice" == "auto_btrfs" ]]; then
        prompt "Do you want to install btrfs-progs for BTRFS filesystem management? (yes/no): " install_btrfs
        if [[ "$install_btrfs" =~ ^[Yy][Ee][Ss]|[Yy]$ ]]; then
            install_pkgs+=("btrfs-progs")
        fi
    fi
    [[ -n "$microcode_pkg" ]] && install_pkgs+=("$microcode_pkg")
    prompt "Do you want to enable the multilib repository for 32-bit software support? (yes/no): " enable_multilib
    prompt "Do you want to apply pacman improvements (enable colors and parallel downloads)? (yes/no): " improve_pacman
    export install_pkgs
}

# ... [other system installation functions unchanged] ...

setup_skel_xdg() {
    log "Setting up /etc/skel for strict XDG and Zsh (with ZDOTDIR)"
    for dir in \
        /mnt/etc/skel/.config \
        /mnt/etc/skel/.cache \
        /mnt/etc/skel/.local/share \
        /mnt/etc/skel/.local/state \
        /mnt/etc/skel/.config/zsh \
        /mnt/etc/skel/.cache/zsh \
        /mnt/etc/skel/.local/state/zsh \
        /mnt/etc/skel/.local/bin
    do
        mkdir -p "$dir"
    done
    chmod 700 /mnt/etc/skel/.local/bin

    # Minimal starter zshrc in XDG location
    cat > /mnt/etc/skel/.config/zsh/.zshrc <<'EOF'
# ~/.config/zsh/.zshrc
export PATH="$HOME/.local/bin:$PATH"
# Add your Zsh config here.
EOF
}

setup_systemwide_zshenv() {
    log "Writing system-wide /etc/zsh/zshenv for strict XDG and ZDOTDIR"
    arch-chroot /mnt mkdir -p /etc/zsh
    cat > /mnt/etc/zsh/zshenv <<'EOF'
# XDG Base Directory Specification variables (system-wide)
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
EOF
}

set_systemwide_default_shell() {
    log "Setting system-wide default shell to zsh for new users"
    sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /mnt/etc/default/useradd
}

copy_skel_to_root() {
    log "Copying /etc/skel to /root"
    arch-chroot /mnt cp -aT /etc/skel /root
    arch-chroot /mnt chmod -R go-w /root
}

set_root_shell() {
    log "Setting root shell to zsh"
    arch-chroot /mnt chsh -s /bin/zsh root
}

# ... [user account and sudo config functions unchanged] ...

#-----------------------------------------------------------
# MAIN INSTALL PROCESS
#-----------------------------------------------------------

main() {
    log "Starting Arch Linux installation..."
    check_internet || exit 1
    check_uefi || exit 1
    create_disk_menu
    wipe_partitions "$selected_disk"
    create_partition_menu
    perform_partitioning "$selected_disk" "$partition_choice"
    select_install_packages
    install_base_system || exit 1
    configure_initramfs || exit 1
    setup_network || exit 1
    configure_system || exit 1

    setup_skel_xdg || exit 1
    setup_systemwide_zshenv || exit 1
    set_systemwide_default_shell || exit 1
    setup_user_accounts || exit 1
    copy_skel_to_root || exit 1
    set_root_shell || exit 1

    install_bootloader || exit 1
    log "Installation completed successfully!"
    log "You can now reboot into your new Arch Linux system."
    log "Remember to remove the installation media before rebooting."
}

#-----------------------------------------------------------
# Script Initialization
#-----------------------------------------------------------
trap 'handle_error ${LINENO}' ERR
check_root
init_log
check_boot_media "$@"
main
exit 0
