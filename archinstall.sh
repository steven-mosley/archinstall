#!/bin/bash

#===========================================================
# Arch Linux Installation Script
# - Automates Arch Linux installation with UEFI boot
# - Supports BTRFS auto partitioning and manual setup
# - Performs system configuration and user setup
#===========================================================

readonly LOG_FILE="/var/log/archinstall.log"
readonly MIN_DISK_SIZE=$((20 * 1024 * 1024 * 1024)) # 20GB in bytes

#-----------------------------------------------------------
# Core Utilities
#-----------------------------------------------------------

# Initialize log file
init_log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
}

# Log messages to console and log file
log() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    log "ERROR on line $line_number: Command exited with status $exit_code"
    log "Installation failed. See log file at $LOG_FILE for details."
    exit $exit_code
}

# Safely prompt user for input (stdout > /dev/tty)
prompt() {
    local message="$1"
    local varname="$2"
    echo "$message" > /dev/tty
    read -r "$varname" < /dev/tty
}

# Confirm destructive operations
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

# Ensure script runs as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
}

# Validate Boot Media: Ensure running from official Arch ISO
check_boot_media() {
    # Official Arch ISOs set up /run/archiso
    if [ -d /run/archiso ]; then
        return 0
    fi

    # Check for the override flag
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

# Check Internet connectivity
check_internet() {
    log "Checking internet connectivity..."
    if ! ping -c 1 archlinux.org &>/dev/null; then
        log "ERROR: No internet connection detected"
        exit 1
    fi
    log "Internet connection verified"
}

# Check if system is booted in UEFI mode
check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        log "ERROR: System not booted in UEFI mode"
        exit 1
    fi
    log "UEFI boot mode verified"
}

# Verify disk space
verify_disk_space() {
    local disk="$1"
    
    # Check if device exists
    if [[ ! -b "$disk" ]]; then
        log "ERROR: Disk $disk does not exist or is not a block device"
        return 1
    fi
    
    # Get disk size in a more resilient way
    local disk_size
    disk_size=$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)
    
    # If blockdev failed, try alternative method
    if [[ "$disk_size" -eq 0 ]]; then
        disk_size=$(lsblk -b -n -o SIZE "$disk" 2>/dev/null | head -n1 || echo 0)
    fi
    
    # QEMU environment check - if disk is too small but has "QEMU" in its name/model, proceed anyway
    local disk_model
    disk_model=$(lsblk -n -o MODEL "$disk" 2>/dev/null | tr -d ' ' || echo "")
    
    if [[ "$disk_model" == *"QEMU"* || "$disk_model" == *"VBOX"* ]]; then
        log "QEMU/VirtualBox disk detected: $disk. Skipping size verification."
        return 0
    fi
    
    if ((disk_size < MIN_DISK_SIZE)); then
        # Try to display human-readable size if numfmt is available
        if command -v numfmt >/dev/null 2>&1; then
            log "ERROR: Disk size ($(numfmt --to=iec-i --suffix=B ${disk_size})) is too small."
            log "Minimum required: $(numfmt --to=iec-i --suffix=B ${MIN_DISK_SIZE})"
        else
            log "ERROR: Disk size (${disk_size} bytes) is too small."
            log "Minimum required: ${MIN_DISK_SIZE} bytes (approx. 20GB)"
        fi
        return 1
    fi
    
    # Log the disk size in a friendly format if possible
    if command -v numfmt >/dev/null 2>&1; then
        log "Disk size verified: $(numfmt --to=iec-i --suffix=B ${disk_size})"
    else
        log "Disk size verified: ${disk_size} bytes"
    fi
    return 0
}

#-----------------------------------------------------------
# Disk and Partition Management
#-----------------------------------------------------------

# List all non-loop, non-ROM block devices for user selection
create_disk_menu() {
    log "Listing available disks..."
    echo "Available Disks (excluding loop devices and CD-ROMs):" > /dev/tty
    lsblk -d -p -n -o NAME,SIZE,MODEL,TYPE \
        | grep -E "disk" \
        | grep -v loop \
        | nl \
        > /dev/tty

    prompt "Enter the number corresponding to your disk: " disk_number

    selected_disk=$(lsblk -d -p -n -o NAME,TYPE \
        | grep disk \
        | grep -v loop \
        | awk '{print $1}' \
        | sed -n "${disk_number}p")

    if [[ -z "$selected_disk" ]]; then
        log "Invalid disk selection"
        create_disk_menu
        return
    fi
    
    log "Selected disk: $selected_disk"
    
    # Verify disk is large enough
    verify_disk_space "$selected_disk" || {
        log "Please select a larger disk"
        create_disk_menu
    }
}

# Prompt user for partition scheme
create_partition_menu() {
    log "Selecting partitioning scheme..."
    echo "Partitioning Scheme Options:" > /dev/tty
    echo "1) Automatic partitioning (BTRFS)" > /dev/tty
    echo "2) Manual partitioning (cfdisk)" > /dev/tty

    prompt "Enter your choice (1-2): " choice
    case "$choice" in
        1) partition_choice="auto_btrfs" ;;
        2) partition_choice="manual" ;;
        *) 
            log "Invalid partitioning choice"
            create_partition_menu
            return
            ;;
    esac
    
    log "Selected partitioning scheme: $partition_choice"
}

# Get correct partition name based on disk type
get_partition_name() {
    local disk="$1"
    local part_num="$2"

    if [[ "$disk" =~ nvme[0-9]+n[0-9]+$ ]]; then
        echo "${disk}p${part_num}"
    else
        echo "${disk}${part_num}"
    fi
}

# Unmount & swapoff everything on selected disk, then wipe partitions
wipe_partitions() {
    local disk="$1"
    
    # Sanity check - make sure the disk exists
    if [[ ! -b "$disk" ]]; then
        log "ERROR: Disk $disk does not exist or is not a block device"
        exit 1
    fi
    
    # Show mounted partitions and ask for confirmation
    log "Checking for mounted partitions on $disk..."
    local mounted_parts
    mounted_parts=$(lsblk -n -o NAME,MOUNTPOINT "$disk" 2>/dev/null | awk '$2 != "" {print $1}' || echo "")
    
    if [[ -n "$mounted_parts" ]]; then
        log "The following partitions are currently mounted:"
        lsblk -n -o NAME,MOUNTPOINT "$disk" 2>/dev/null | grep -v "^$disk " > /dev/tty
    fi

    # Check if it's QEMU/Virtual disk to skip confirmation in automated environments
    local disk_model
    disk_model=$(lsblk -n -o MODEL "$disk" 2>/dev/null | tr -d ' ' || echo "")
    
    if [[ "$disk_model" == *"QEMU"* || "$disk_model" == *"VBOX"* ]]; then
        log "QEMU/VirtualBox disk detected: $disk. Proceeding without confirmation."
    else
        if ! confirm_operation "WARNING: All data on $disk will be erased. Continue?"; then
            exit 1
        fi
    fi

    log "Unmounting partitions and disabling swap on $disk..."
    # Get partition list safely
    local partitions
    partitions=$(lsblk -n -o NAME "$disk" 2>/dev/null | grep -v "^$(basename "$disk")$" || echo "")
    
    if [[ -n "$partitions" ]]; then
        for part in $partitions; do
            if [[ -b "/dev/$part" ]]; then
                log "Unmounting /dev/$part if mounted..."
                umount -f "/dev/$part" 2>/dev/null || true
                swapoff "/dev/$part" 2>/dev/null || true
            fi
        done
    else
        log "No partitions found on $disk"
    fi

    log "Wiping disk signatures on $disk..."
    if ! wipefs -a "$disk" 2>/dev/null; then
        log "WARNING: Failed to wipe disk signatures, attempting alternative method"
        # Alternative method for wiping disk
        dd if=/dev/zero of="$disk" bs=512 count=1 conv=notrunc 2>/dev/null || {
            log "ERROR: Failed to zero out disk. Continuing anyway..."
        }
    fi
    
    log "Creating new GPT partition table on $disk..."
    if ! parted -s "$disk" mklabel gpt 2>/dev/null; then
        log "WARNING: Failed with parted, trying fdisk alternative"
        echo -e "g\nw\n" | fdisk "$disk" 2>/dev/null || {
            log "ERROR: All methods to create GPT table failed. Aborting."
            exit 1
        }
    fi
    
    # Double-check that the partition table was created
    if ! parted -s "$disk" print 2>/dev/null | grep -q "Partition Table: gpt"; then
        log "WARNING: GPT partition table may not have been created correctly"
    fi
    
    log "Disk $disk has been prepared with a clean GPT partition table"
    # Sleep to give the system time to recognize the new partition table
    sleep 2
}

# Calculate swap size as half of RAM (in MiB)
calculate_swap_size() {
    local ram_kB
    ram_kB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local swap_mib=$(( ram_kB / 2 / 1024 ))
    echo "$swap_mib"
}

# Perform chosen partitioning scheme
perform_partitioning() {
    local disk="$1"
    local choice="$2"
    local swap_size
    swap_size=$(calculate_swap_size)

    log "Calculating swap size: ${swap_size}MiB"

    case "$choice" in
        "auto_btrfs")
            log "Performing automatic partitioning (BTRFS) on $disk"
            local esp=$(get_partition_name "$disk" 1)
            local swp=$(get_partition_name "$disk" 2)
            local root=$(get_partition_name "$disk" 3)

            log "Creating partitions..."
            parted -s "$disk" mkpart primary fat32 1MiB 513MiB || { 
                log "ERROR: Failed to create EFI partition"
                exit 1
            }
            parted -s "$disk" set 1 esp on || {
                log "ERROR: Failed to set ESP flag"
                exit 1
            }
            parted -s "$disk" mkpart primary linux-swap 513MiB "$((513 + swap_size))MiB" || {
                log "ERROR: Failed to create swap partition"
                exit 1
            }
            parted -s "$disk" mkpart primary btrfs "$((513 + swap_size))MiB" 100% || {
                log "ERROR: Failed to create root partition"
                exit 1
            }

            log "Refreshing partition table..."
            partprobe "$disk" || {
                log "ERROR: Failed to refresh partition table"
                sleep 2  # Give the system a moment to recognize the new partitions
            }

            log "Wiping filesystem signatures from new partitions..."
            wipefs -a "$esp" "$swp" "$root" || {
                log "WARNING: Failed to wipe some filesystem signatures"
            }

            log "Formatting EFI partition ($esp)..."
            mkfs.fat -F32 "$esp" || {
                log "ERROR: Failed to format EFI partition"
                exit 1
            }

            log "Creating and activating swap ($swp)..."
            mkswap "$swp" || {
                log "ERROR: Failed to create swap"
                exit 1
            }
            swapon "$swp" || {
                log "WARNING: Failed to activate swap"
            }

            log "Formatting BTRFS root partition ($root)..."
            mkfs.btrfs -f "$root" || {
                log "ERROR: Failed to format BTRFS partition"
                exit 1
            }

            log "Creating BTRFS subvolumes..."
            mount "$root" /mnt || {
                log "ERROR: Failed to mount BTRFS root partition"
                exit 1
            }
            
            btrfs subvolume create /mnt/@ && \
            btrfs subvolume create /mnt/@home && \
            btrfs subvolume create /mnt/@log && \
            btrfs subvolume create /mnt/@pkg || {
                log "ERROR: Failed to create BTRFS subvolumes"
                umount /mnt
                exit 1
            }
            
            umount /mnt

            log "Mounting BTRFS subvolumes..."
            local btrfs_opts="compress=zstd,noatime,space_cache=v2"
            mount -o "subvol=@,$btrfs_opts" "$root" /mnt || {
                log "ERROR: Failed to mount @ subvolume"
                exit 1
            }
            
            mkdir -p /mnt/{efi,home,var/log,var/cache/pacman/pkg} || {
                log "ERROR: Failed to create mount directories"
                exit 1
            }
            
            mount -o "subvol=@home,$btrfs_opts" "$root" /mnt/home && \
            mount -o "subvol=@log,$btrfs_opts" "$root" /mnt/var/log && \
            mount -o "subvol=@pkg,$btrfs_opts" "$root" /mnt/var/cache/pacman/pkg || {
                log "ERROR: Failed to mount BTRFS subvolumes"
                exit 1
            }
            
            mount "$esp" /mnt/efi || {
                log "ERROR: Failed to mount EFI partition"
                exit 1
            }
            
            log "All partitions created and mounted successfully"
            ;;
        
        "manual")
            log "Launching cfdisk for manual partitioning on $disk..."
            cfdisk "$disk"
            log "Manual partitioning completed. You must format and mount partitions yourself."
            log "IMPORTANT: Mount your root partition to /mnt and any others as needed."
            log "Press Enter when all partitions are mounted and ready to proceed."
            read -r < /dev/tty
            
            # Verify root mount
            if ! mountpoint -q /mnt; then
                log "ERROR: /mnt is not mounted. Mount your root partition to /mnt first."
                exit 1
            fi
            
            # Verify EFI mount
            if ! mountpoint -q /mnt/efi && ! mountpoint -q /mnt/boot/efi; then
                log "ERROR: EFI partition not mounted at /mnt/efi or /mnt/boot/efi"
                exit 1
            fi
            ;;
    esac
}

#-----------------------------------------------------------
# System Installation and Configuration
#-----------------------------------------------------------

# Installs Arch base system into /mnt
install_base_system() {
    if ! mountpoint -q /mnt; then
        log "ERROR: /mnt is not mounted. Cannot install base system."
        return 1
    fi

    prompt "Do you want to use zsh as your default shell? (yes/no): " use_zsh

    log "Installing essential packages..."
    local packages="base linux linux-firmware sudo"
    
    if [[ "$partition_choice" == "auto_btrfs" ]]; then
        packages="$packages btrfs-progs"
    fi
    
    if [[ "$use_zsh" =~ ^[Yy][Ee][Ss]|[Yy]$ ]]; then
        packages="$packages zsh"
    fi
    
    log "Installing: $packages"
    if ! pacstrap -K /mnt $packages; then
        log "ERROR: Failed to install base system"
        return 1
    fi
    
    log "Generating fstab..."
    if ! genfstab -U /mnt >> /mnt/etc/fstab; then
        log "ERROR: Failed to generate fstab"
        return 1
    fi
    
    log "Base system installed successfully"
    return 0
}

# Detect CPU type and install appropriate microcode
install_microcode() {
    log "Detecting CPU type for microcode..."
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        log "Intel CPU detected, installing intel-ucode..."
        arch-chroot /mnt pacman -S --noconfirm intel-ucode
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        log "AMD CPU detected, installing amd-ucode..."
        arch-chroot /mnt pacman -S --noconfirm amd-ucode
    else
        log "CPU type not definitively detected, installing both microcode packages..."
        arch-chroot /mnt pacman -S --noconfirm intel-ucode amd-ucode
    fi
}

# Setup network configuration
setup_network() {
    if ! mountpoint -q /mnt; then
        log "ERROR: /mnt is not mounted. Cannot configure network."
        return 1
    fi
    
    log "Installing and enabling NetworkManager..."
    # Try to update the package database first
    if ! arch-chroot /mnt pacman -Sy; then
        log "WARNING: Failed to update package database. Network may be unavailable."
    fi
    
    # Try to install NetworkManager with retry logic
    local attempts=0
    local max_attempts=3
    
    while [ $attempts -lt $max_attempts ]; do
        if arch-chroot /mnt pacman -S --noconfirm networkmanager; then
            break
        else
            attempts=$((attempts + 1))
            if [ $attempts -lt $max_attempts ]; then
                log "Attempt $attempts of $max_attempts failed. Retrying in 5 seconds..."
                sleep 5
            else
                log "ERROR: Failed to install NetworkManager after $max_attempts attempts."
                log "NOTE: In a virtual environment, this may be due to network connectivity issues."
                log "You can manually install NetworkManager after boot with 'pacman -S networkmanager'"
                # Don't return error to allow installation to continue
                break
            fi
        fi
    done
    
    # Try to enable the service, but continue even if it fails
    if ! arch-chroot /mnt systemctl enable NetworkManager.service; then
        log "WARNING: Failed to enable NetworkManager service."
        log "You can manually enable it after boot with 'systemctl enable NetworkManager.service'"
    else
        log "NetworkManager service enabled successfully"
    fi
    
    return 0
}

# Configure system settings (locale, hostname, time, etc.)
configure_system() {
    if ! mountpoint -q /mnt; then
        log "ERROR: /mnt is not mounted. Cannot configure system."
        return 1
    fi
    
    log "Configuring system settings..."

    # Define available locales
    locales=(
        "en_US.UTF-8 UTF-8"
        "en_GB.UTF-8 UTF-8"
        "fr_FR.UTF-8 UTF-8"
        "de_DE.UTF-8 UTF-8"
    )

    # Prompt for locale selection
    echo "Available Locales:" > /dev/tty
    for i in "${!locales[@]}"; do
        echo "$((i + 1)). ${locales[$i]}" > /dev/tty
    done

    while :; do
        prompt "Select your locale (1-${#locales[@]}): " locale_choice
        if [[ "$locale_choice" =~ ^[1-${#locales[@]}]$ ]]; then
            selected_locale="${locales[$((locale_choice - 1))]}"
            break
        else
            log "Invalid choice. Try again."
        fi
    done

    # Configure locale
    log "Setting up locale: $selected_locale"
    echo "$selected_locale" > /mnt/etc/locale.gen || {
        log "ERROR: Failed to create locale.gen"
        return 1
    }
    
    arch-chroot /mnt locale-gen || {
        log "ERROR: Failed to generate locales"
        return 1
    }
    
    echo "LANG=$(echo "$selected_locale" | awk '{print $1}')" > /mnt/etc/locale.conf || {
        log "ERROR: Failed to set locale.conf"
        return 1
    }

    # Configure hostname
    prompt "Enter your desired hostname: " hostname
    echo "$hostname" > /mnt/etc/hostname || {
        log "ERROR: Failed to set hostname"
        return 1
    }

    # Configure hosts file
    {
        echo "127.0.0.1    localhost"
        echo "::1          localhost"
        echo "127.0.1.1    $hostname.localdomain $hostname"
    } > /mnt/etc/hosts || {
        log "ERROR: Failed to configure hosts file"
        return 1
    }

    # Set timezone based on IP geolocation or prompt if unavailable
    log "Setting timezone..."
    local timezone
    timezone=$(curl -s https://ipapi.co/timezone 2>/dev/null)
    
    if [[ -z "$timezone" || ! -f "/usr/share/zoneinfo/$timezone" ]]; then
        log "Could not auto-detect timezone. Please enter it manually."
        prompt "Enter your timezone (e.g., America/New_York): " timezone
        
        if [[ ! -f "/usr/share/zoneinfo/$timezone" ]]; then
            log "Invalid timezone. Using UTC as fallback."
            timezone="UTC"
        fi
    fi
    
    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime || {
        log "ERROR: Failed to set timezone to $timezone"
        return 1
    }
    
    arch-chroot /mnt hwclock --systohc || {
        log "WARNING: Failed to set hardware clock"
    }

    # Set root password
    log "Setting root password (you will be prompted in chroot):"
    while ! arch-chroot /mnt passwd; do
        log "Password setting failed. Please try again."
    done
    
    # Install bootloader
    log "Installing GRUB bootloader..."
    arch-chroot /mnt pacman -S --noconfirm grub efibootmgr || {
        log "ERROR: Failed to install GRUB"
        return 1
    }
    
    # Install CPU microcode before configuring GRUB
    install_microcode
    
    local efi_dir="/efi"
    if [[ ! -d "/mnt$efi_dir" && -d "/mnt/boot/efi" ]]; then
        efi_dir="/boot/efi"
    fi
    
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory="$efi_dir" --bootloader-id=GRUB || {
        log "ERROR: Failed to install GRUB bootloader"
        return 1
    }
    
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg || {
        log "ERROR: Failed to generate GRUB configuration"
        return 1
    }
    
    log "System configuration completed successfully"
    return 0
}

#-----------------------------------------------------------
# User Account Setup
#-----------------------------------------------------------

# Create a new user account
create_user_account() {
    local username
    
    while true; do
        prompt "Enter username (lowercase letters, numbers, or underscore, 3-32 chars): " username
        if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{2,31}$ ]]; then
            log "ERROR: Invalid username format. Please try again."
            continue
        fi
        if grep -q "^$username:" /mnt/etc/passwd 2>/dev/null; then
            log "ERROR: Username '$username' already exists."
            continue
        fi
        local reserved_names=("root" "daemon" "bin" "sys" "sync" "games" "man" "lp" "mail" "news" "uucp" "proxy" "www-data" "backup" "list" "irc" "gnats" "nobody" "systemd-network" "systemd-resolve" "messagebus" "systemd-timesync" "polkitd")
        if [[ " ${reserved_names[@]} " =~ " ${username} " ]]; then
            log "ERROR: Username '$username' is reserved. Please choose another."
            continue
        fi
        break
    done
    
    log "Creating user account for $username..."
    arch-chroot /mnt useradd -mG wheel -s /bin/bash "$username" || {
        log "ERROR: Failed to create user account"
        return 1
    }
    
    log "Setting password for user $username..."
    while ! arch-chroot /mnt passwd "$username"; do
        log "Password setting failed. Please try again."
    done

    setup_user_environment "$username"
    return 0
}

# Setup user environment files
setup_user_environment() {
    local username="$1"
    local user_home="/home/$username"
    
    log "Setting up user environment for $username..."
    
    cat > "/mnt$user_home/.bashrc" <<EOF
# User's .bashrc configuration
[[ \$- != *i* ]] && return

alias ls='ls --color=auto'
alias ll='ls -la'
alias grep='grep --color=auto'
alias ip='ip -color=auto'

# Set a more informative prompt
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
EOF

    # Create user's .config directory
    mkdir -p "/mnt$user_home/.config" || {
        log "WARNING: Failed to create user config directory"
    }
    
    # Set permissions
    arch-chroot /mnt chown -R "$username:$username" "$user_home" || {
        log "WARNING: Failed to set permissions on user home directory"
    }
}

# Configure sudo access for the user
configure_sudo_access() {
    log "Configuring sudo access..."
    arch-chroot /mnt mkdir -p /etc/sudoers.d || {
        log "ERROR: Failed to create sudoers.d directory"
        return 1
    }
    
    # Configure wheel group for sudo
    arch-chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers || {
        log "ERROR: Failed to configure sudo access"
        return 1
    }
    
    # Verify sudoers syntax
    if ! arch-chroot /mnt visudo -c; then
        log "ERROR: Sudo configuration syntax error detected"
        return 1
    fi
    
    log "Sudo access configured successfully"
    return 0
}

# Main user setup function
setup_user_accounts() {
    log "Setting up user accounts..."
    create_user_account || {
        log "ERROR: Failed to create user account"
        return 1
    }
    configure_sudo_access || {
        log "ERROR: Failed to configure sudo access"
        return 1
    }
    log "User account setup completed successfully"
    return 0
}

#-----------------------------------------------------------
# Main Installation Process
#-----------------------------------------------------------

main() {
    log "Starting Arch Linux installation..."
    
    # Pre-installation checks
    check_internet || exit 1
    check_uefi || exit 1
    
    # Disk preparation
    create_disk_menu
    wipe_partitions "$selected_disk"
    create_partition_menu
    perform_partitioning "$selected_disk" "$partition_choice"

    # System installation
    install_base_system || exit 1
    setup_network || exit 1
    configure_system || exit 1
    setup_user_accounts || exit 1
    
    log "Installation completed successfully!"
    log "You can now reboot into your new Arch Linux system."
    log "Remember to remove the installation media before rebooting."
}

#-----------------------------------------------------------
# Script Initialization
#-----------------------------------------------------------

# Initialize error handling
trap 'handle_error ${LINENO}' ERR

# Check if running as root
check_root

# Initialize log file
init_log

# Validate boot media before proceeding
check_boot_media "$@"

# Run the main installation process
main

exit 0
