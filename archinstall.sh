#!/bin/bash

#===========================================================
# Arch Linux Installation Script
# - Unmounts & disables swap on selected disk
# - Wipes existing partitions and signatures thoroughly
# - Supports ext4 or BTRFS auto partitioning and manual
#===========================================================

# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Exiting."
  exit 1
fi

readonly LOG_FILE="/var/log/archinstall.log"

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
    log "Error on line $line_number: Command exited with status $exit_code"
    exit $exit_code
}

# Add error trap
trap 'handle_error ${LINENO}' ERR

#-----------------------------------------------------------
# Validate Boot Media: Ensure running from official Arch ISO
#-----------------------------------------------------------
check_boot_media() {
    # Official Arch ISOs set up /run/archiso; its absence indicates unofficial boot media.
    if [ -d /run/archiso ]; then
        return 0
    fi

    # Check for the --unsupported-boot-media flag among script arguments.
    local proceed=0
    for arg in "$@"; do
        if [ "$arg" = "--unsupported-boot-media" ]; then
            proceed=1
            break
        fi
    done

    if [ "$proceed" -ne 1 ]; then
        log "ERROR: Unofficial boot media detected. This script is only supported on an official Arch ISO. Rerun with the --unsupported-boot-media flag if you wish to proceed."
        exit 1
    fi
}

#-----------------------------------------------------------
# Check Internet connectivity
#-----------------------------------------------------------
check_internet() {
    log "Checking internet connectivity..."
    if ! ping -c 1 archlinux.org &>/dev/null; then
        log "ERROR: No internet connection detected"
        exit 1
    fi
}

#-----------------------------------------------------------
# Check if system is booted in UEFI mode
#-----------------------------------------------------------
check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        log "ERROR: System not booted in UEFI mode"
        exit 1
    fi
}

#-----------------------------------------------------------
# Safely prompt user for input (stdout > /dev/tty)
#-----------------------------------------------------------
prompt() {
  local message="$1"
  local varname="$2"
  echo "$message" > /dev/tty
  read -r "$varname" < /dev/tty
}

#-----------------------------------------------------------
# List all non-loop, non-ROM block devices for user selection
#-----------------------------------------------------------
create_disk_menu() {
  echo "Available Disks (excluding loop and CD-ROM):" > /dev/tty
  lsblk -d -p -n -o NAME,SIZE,TYPE \
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
    echo "Invalid selection. Please try again." > /dev/tty
    create_disk_menu
  else
    echo "Selected disk: $selected_disk" > /dev/tty
  fi
}

#-----------------------------------------------------------
# Prompt user for partition scheme
#-----------------------------------------------------------
create_partition_menu() {
  echo "Partitioning Scheme Options:" > /dev/tty
  echo "1) Automatic partitioning (ext4)" > /dev/tty
  echo "2) Automatic partitioning (BTRFS)" > /dev/tty
  echo "3) Manual partitioning (cfdisk)" > /dev/tty

  prompt "Enter your choice (1-3): " choice
  case "$choice" in
    1) partition_choice="auto_ext4" ;;
    2) partition_choice="auto_btrfs" ;;
    3) partition_choice="manual" ;;
    *) 
       echo "Invalid choice. Try again." > /dev/tty
       create_partition_menu
       ;;
  esac
}

#-----------------------------------------------------------
# For a disk like /dev/nvme0n1, we must append 'p' for partition;
# for /dev/sda or /dev/vda, just append the digit.
#-----------------------------------------------------------
get_partition_name() {
  local disk="$1"
  local part_num="$2"

  if [[ "$disk" =~ nvme[0-9]+n[0-9]+$ ]]; then
    echo "${disk}p${part_num}"
  else
    echo "${disk}${part_num}"
  fi
}

#-----------------------------------------------------------
# Verify disk space
#-----------------------------------------------------------
verify_disk_space() {
    local disk="$1"
    local min_size=$((20 * 1024 * 1024 * 1024)) # 20GB in bytes
    
    local disk_size
    disk_size=$(blockdev --getsize64 "$disk")
    
    if ((disk_size < min_size)); then
        log "ERROR: Disk size (${disk_size} bytes) is too small. Minimum required: ${min_size} bytes"
        return 1
    fi
}

#-----------------------------------------------------------
# Unmount & swapoff everything on $selected_disk, then wipe partitions
#-----------------------------------------------------------
wipe_partitions() {
  echo "Wiping existing partitions on $selected_disk..." > /dev/tty

  for part in $(lsblk -n -o NAME "$selected_disk"); do
    if [[ -b "/dev/$part" ]]; then
      umount -R "/dev/$part" 2>/dev/null || true
      swapoff "/dev/$part" 2>/dev/null || true
    fi
  done

  wipefs -a "$selected_disk"
  parted -s "$selected_disk" mklabel gpt
  echo "GPT partition table created on $selected_disk" > /dev/tty
}

#-----------------------------------------------------------
# Return swap in MiB as half the total system RAM
#-----------------------------------------------------------
calculate_swap_size() {
  local ram_kB
  ram_kB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local swap_mib=$(( ram_kB / 2 / 1024 ))
  echo "$swap_mib"
}

#-----------------------------------------------------------
# Automatic or manual partitioning.
#   auto_ext4  -> (ESP, swap, root ext4)
#   auto_btrfs -> (ESP, swap, root BTRFS)
#   manual     -> Launch cfdisk for user-driven partitioning
#-----------------------------------------------------------
perform_partitioning() {
  local disk="$1"
  local choice="$2"
  local swap_size
  swap_size=$(calculate_swap_size)

  case "$choice" in
    "auto_ext4")
        echo "Performing automatic partitioning (ext4) on $disk" > /dev/tty
        local esp=$(get_partition_name "$disk" 1)
        local swp=$(get_partition_name "$disk" 2)
        local root=$(get_partition_name "$disk" 3)

        parted -s "$disk" mkpart primary fat32 1MiB 513MiB
        parted -s "$disk" set 1 esp on
        parted -s "$disk" mkpart primary linux-swap 513MiB "$((513 + swap_size))MiB"
        parted -s "$disk" mkpart primary ext4 "$((513 + swap_size))MiB" 100%

        partprobe "$disk"
        wipefs -a "$esp"
        wipefs -a "$swp"
        wipefs -a "$root"

        mkfs.fat -F32 -I "$esp"
        mkswap "$swp"
        swapon "$swp"
        mkfs.ext4 -F "$root"

        mount "$root" /mnt
        mkdir -p /mnt/efi
        mount "$esp" /mnt/efi
        ;;
    
    "auto_btrfs")
        echo "Performing automatic partitioning (BTRFS) on $disk" > /dev/tty
        local esp=$(get_partition_name "$disk" 1)
        local swp=$(get_partition_name "$disk" 2)
        local root=$(get_partition_name "$disk" 3)

        parted -s "$disk" mkpart primary fat32 1MiB 513MiB
        parted -s "$disk" set 1 esp on
        parted -s "$disk" mkpart primary linux-swap 513MiB "$((513 + swap_size))MiB"
        parted -s "$disk" mkpart primary btrfs "$((513 + swap_size))MiB" 100%

        partprobe "$disk"
        wipefs -a "$esp"
        wipefs -a "$swp"
        wipefs -a "$root"

        mkfs.fat -F32 -I "$esp"
        mkswap "$swp"
        swapon "$swp"
        mkfs.btrfs -f "$root"

        mount "$root" /mnt
        btrfs subvolume create /mnt/@
        btrfs subvolume create /mnt/@home
        btrfs subvolume create /mnt/@log
        btrfs subvolume create /mnt/@pkg
        btrfs subvolume create /mnt/@snapshots
        umount /mnt

        mount -o subvol=@,compress=zstd,noatime "$root" /mnt
        mkdir -p /mnt/{efi,home,var/log,var/cache/pacman/pkg,.snapshots}
        mount -o subvol=@home,compress=zstd,noatime "$root" /mnt/home
        mount -o subvol=@log,compress=zstd,noatime "$root" /mnt/var/log
        mount -o subvol=@pkg,compress=zstd,noatime "$root" /mnt/var/cache/pacman/pkg
        mount -o subvol=@snapshots,compress=zstd,noatime "$root" /mnt/.snapshots
        mount "$esp" /mnt/efi
        ;;
    
    "manual")
        echo "Launching cfdisk for manual partitioning on $disk..." > /dev/tty
        cfdisk "$disk"
        ;;
  esac
}

create_user_account() {
    local username
    local -a additional_groups=("wheel" "users" "storage" "power" "audio" "video" "optical")
    
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
    
    log "Creating user account..."
    arch-chroot /mnt useradd -m -G "$(IFS=,; echo "${additional_groups[*]}")" -s /bin/bash "$username"
    
    log "Setting password for user $username..."
    while ! arch-chroot /mnt passwd "$username"; do
        log "Password setting failed. Please try again."
    done

    setup_user_environment "$username"
    return 0
}

setup_user_environment() {
    local username="$1"
    local user_home="/home/$username"
    cat > "/mnt$user_home/.bashrc" <<EOF
# User's .bashrc configuration
[[ \$- != *i* ]] && return

alias grep='grep --color=auto'
alias ip='ip -color=auto'

# Set a more informative prompt
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
EOF
}

#-----------------------------------------------------------
# Configure sudo access for the user
#-----------------------------------------------------------
configure_sudo_access() {
    local username="$1"
    arch-chroot /mnt mkdir -p /etc/sudoers.d
    arch-chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    if ! arch-chroot /mnt visudo -c; then
        log "ERROR: Sudo configuration syntax error detected"
        return 1
    fi
}

#-----------------------------------------------------------
# Main user setup function
#-----------------------------------------------------------
setup_user_accounts() {
    log "Setting up user accounts..."
    create_user_account || {
        log "ERROR: Failed to create user account"
        return 1
    }
    configure_sudo_access "$username" || {
        log "ERROR: Failed to configure sudo access"
        return 1
    }
    log "User account setup completed successfully"
    return 0
}

#-----------------------------------------------------------
# Installs Arch base system into /mnt
#-----------------------------------------------------------
install_base_system() {
    if ! mountpoint -q /mnt; then
        log "ERROR: /mnt is not mounted. Cannot install base system."
        return 1
    fi

    prompt "Do you want to use zsh as your default shell? (yes/no): " use_zsh

    if [[ "$partition_choice" == "auto_btrfs" ]]; then
        if [[ "$use_zsh" =~ ^[Yy][Ee][Ss]|[Yy]$ ]]; then
            log "Installing base system (base, linux, linux-firmware, sudo, btrfs-progs, zsh)..."
            pacstrap -K /mnt base linux linux-firmware sudo btrfs-progs zsh
        else
            log "Installing base system (base, linux, linux-firmware, sudo, btrfs-progs)..."
            pacstrap -K /mnt base linux linux-firmware sudo btrfs-progs
        fi
    else
        if [[ "$use_zsh" =~ ^[Yy][Ee][Ss]|[Yy]$ ]]; then
            log "Installing base system (base, linux, linux-firmware, sudo, zsh)..."
            pacstrap -K /mnt base linux linux-firmware sudo zsh
        else
            log "Installing base system (base, linux, linux-firmware, sudo)..."
            pacstrap -K /mnt base linux linux-firmware sudo
        fi
    fi

    genfstab -U /mnt >> /mnt/etc/fstab
}

#-----------------------------------------------------------
# Setup network configuration
#-----------------------------------------------------------
setup_network() {
    if ! mountpoint -q /mnt; then
        log "ERROR: /mnt is not mounted. Cannot configure network."
        return 1
    fi
    log "Setting up minimal network configuration..."
    arch-chroot /mnt pacman -S --noconfirm networkmanager
    arch-chroot /mnt systemctl enable NetworkManager.service
}

#-----------------------------------------------------------
# Configure system settings
#-----------------------------------------------------------
configure_system() {
    if ! mountpoint -q /mnt; then
        log "ERROR: /mnt is not mounted. Cannot configure system."
        return 1
    fi
    log "Configuring system..."

    locales=(
        "en_US.UTF-8 UTF-8"
        "en_GB.UTF-8 UTF-8"
        "fr_FR.UTF-8 UTF-8"
        "de_DE.UTF-8 UTF-8"
    )

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

    echo "$selected_locale" > /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=$(echo "$selected_locale" | awk '{print $1}')" > /mnt/etc/locale.conf

    prompt "Enter your desired hostname: " hostname
    echo "$hostname" > /mnt/etc/hostname

    {
        echo "127.0.0.1    localhost"
        echo "::1          localhost"
        echo "127.0.1.1    $hostname.localdomain $hostname"
    } > /mnt/etc/hosts

    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$(curl -s https://ipapi.co/timezone)" /etc/localtime
    arch-chroot /mnt hwclock --systohc

    log "Set the root password (you will be prompted in chroot):"
    arch-chroot /mnt passwd

    log "Installing GRUB bootloader..."
    arch-chroot /mnt pacman -S --noconfirm grub efibootmgr
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

#-----------------------------------------------------------
# Main
#-----------------------------------------------------------
main() {
    create_disk_menu
    wipe_partitions
    create_partition_menu
    perform_partitioning "$selected_disk" "$partition_choice"

    # If manual partitioning was chosen, the user must handle mkfs & mount.
    install_base_system || exit 1

    setup_network
    configure_system
    setup_user_accounts || exit 1
    log "Installation complete! You can now reboot."
}

# Validate boot media before proceeding
check_boot_media "$@"

main
