#!/bin/bash

#===========================================================
# Arch Linux Installation Script with TUI
# - Improved error handling and user feedback
# - Supports ext4 or BTRFS auto partitioning and manual
# - Hardware detection and driver installation
# - Minimal base with optional components
#===========================================================

# Make sure we fail hard and fast
set -e

# Ensure dialog is available
if ! command -v dialog &>/dev/null; then
    echo "Installing dialog for TUI..." 
    pacman -Sy --noconfirm dialog
fi

readonly LOG_FILE="/var/log/archinstall.log"
readonly TMP_DIR=$(mktemp -d)
readonly DIALOG_OK=0
readonly DIALOG_CANCEL=1
readonly DIALOG_ESC=255

# Ensure cleanup on exit
trap 'rm -rf "$TMP_DIR"; exit' EXIT INT TERM

# Fancy logging 
log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    # Also display in dialog if requested
    if [[ "$3" == "display" ]]; then
        dialog --title "Installation Log" --msgbox "$message" 8 60
    fi
}

# Robust error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log "Error on line $line_number: Command exited with status $exit_code" "ERROR" "display"
    dialog --title "FATAL ERROR" --msgbox "The installation failed at line $line_number with error code $exit_code.\n\nCheck $LOG_FILE for details." 10 60
    exit $exit_code
}

# Add error trap
trap 'handle_error ${LINENO}' ERR

# Show a progress gauge for long operations
show_progress() {
    local cmd="$1"
    local msg="$2"
    local success_msg="$3"
    
    # Create a named pipe for progress communication
    local fifo="$TMP_DIR/progress.fifo"
    mkfifo "$fifo"
    
    # Start progress dialog in background
    dialog --title "Working..." --gauge "$msg" 10 70 0 < "$fifo" &
    local dialog_pid=$!
    
    # Execute the command with progress updates
    (
        echo "0" > "$fifo"
        eval "$cmd" > "$TMP_DIR/cmd.log" 2>&1 &
        local cmd_pid=$!
        
        # Update progress while command runs
        local i=0
        while kill -0 $cmd_pid 2>/dev/null; do
            echo "$i" > "$fifo"
            ((i=i+1))
            if [ $i -gt 100 ]; then i=0; fi
            sleep 0.1
        done
        
        # Final update
        wait $cmd_pid
        local status=$?
        echo "100" > "$fifo"
        sleep 0.5
        
        # Save exit status
        echo $status > "$TMP_DIR/cmd.status"
    )
    
    # Get command status
    local status=$(cat "$TMP_DIR/cmd.status")
    
    # Clean up
    rm "$fifo"
    
    if [ $status -eq 0 ]; then
        log "$success_msg" "SUCCESS"
        return 0
    else
        log "Command failed: $(cat "$TMP_DIR/cmd.log")" "ERROR"
        return 1
    fi
}

# Recovery function to prevent leaving systems in unusable state
recovery_failsafe() {
    # If installation fails midway, offer to chroot
    dialog --title "Installation Failed" --yesno "Installation failed at a critical point.\n\nWould you like to enter a chroot environment to manually fix issues?" 10 60
    if [ $? -eq 0 ]; then
        dialog --infobox "Entering chroot environment..." 3 40
        sleep 1
        arch-chroot /mnt /bin/bash
    else
        dialog --msgbox "System may be in an inconsistent state.\nConsider rebooting from installation media and trying again." 8 60
    fi
}

# Validate Boot Media - ensure running from official Arch ISO
check_boot_media() {
    if [ -d /run/archiso ]; then
        return 0
    fi

    local proceed=0
    for arg in "$@"; do
        if [ "$arg" = "--unsupported-boot-media" ]; then
            proceed=1
            break
        fi
    done

    if [ "$proceed" -ne 1 ]; then
        dialog --title "Boot Media Error" --msgbox "Unofficial boot media detected. This script is only supported on an official Arch ISO.\n\nRerun with the --unsupported-boot-media flag if you wish to proceed anyway." 10 60
        exit 1
    fi
}

# Check Internet connectivity
check_internet() {
    dialog --infobox "Checking internet connectivity..." 3 40
    if ! ping -c 1 archlinux.org &>/dev/null; then
        dialog --title "Network Error" --msgbox "No internet connection detected.\n\nPlease establish a connection and try again." 8 50
        exit 1
    fi
}

# Check if system is booted in UEFI mode
check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        dialog --title "Boot Mode Error" --msgbox "System not booted in UEFI mode.\n\nThis script requires UEFI boot." 8 50
        exit 1
    fi
}

# Disk selection with proper TUI
select_disk() {
    local disks=$(lsblk -d -p -n -o NAME,SIZE,MODEL | grep -v loop | grep -v sr | grep -v fd)
    
    if [[ -z "$disks" ]]; then
        dialog --title "Error" --msgbox "No valid disks found!" 5 40
        exit 1
    fi
    
    # Build menu items
    local options=""
    while IFS= read -r line; do
        local disk=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local model=$(echo "$line" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//')
        options="$options $disk \"$size - $model\" "
    done <<< "$disks"
    
    # Show menu and get selection
    selected_disk=$(dialog --stdout --title "Disk Selection" --menu "WARNING: Selected disk will be completely erased!\nChoose carefully:" 15 70 7 $options)
    
    if [[ -z "$selected_disk" ]]; then
        dialog --title "Cancelled" --msgbox "Disk selection cancelled. Exiting." 5 40
        exit 0
    fi
    
    # Confirm destruction
    dialog --title "DESTRUCTION CONFIRMATION" --yesno "WARNING! All data on $selected_disk will be PERMANENTLY DESTROYED!\n\nAre you absolutely sure you want to continue?" 10 60
    
    if [ $? -ne 0 ]; then
        dialog --title "Cancelled" --msgbox "Disk wiping cancelled. Exiting." 5 40
        exit 0
    fi

    # Verify disk space
    local disk_size
    disk_size=$(blockdev --getsize64 "$selected_disk")
    local min_size=$((20 * 1024 * 1024 * 1024)) # 20GB
    
    if ((disk_size < min_size)); then
        dialog --title "Disk Too Small" --msgbox "Disk size ($(numfmt --to=iec-i --suffix=B $disk_size)) is too small.\nMinimum required: 20GiB" 7 50
        exit 1
    fi
}

# Partition scheme selection with TUI
select_partition_scheme() {
    partition_choice=$(dialog --stdout --title "Partitioning Scheme" --menu "Select partitioning scheme:" 12 60 3 \
        "auto_ext4" "Automatic partitioning (ext4)" \
        "auto_btrfs" "Automatic partitioning (BTRFS)" \
        "manual" "Manual partitioning (cfdisk)")
    
    if [[ -z "$partition_choice" ]]; then
        dialog --title "Cancelled" --msgbox "Partitioning selection cancelled. Exiting." 5 40
        exit 0
    fi
}

# For partition naming conventions
get_partition_name() {
    local disk="$1"
    local part_num="$2"

    if [[ "$disk" =~ nvme[0-9]+n[0-9]+$ ]]; then
        echo "${disk}p${part_num}"
    else
        echo "${disk}${part_num}"
    fi
}

# Improved wipe_partitions function with safety
wipe_partitions() {
    dialog --infobox "Unmounting partitions on $selected_disk..." 3 50
    
    # Find all mounted partitions from selected disk
    local partitions=$(lsblk -n -o NAME,MOUNTPOINT "$selected_disk" | grep -v "^$selected_disk " | awk '$2 != "" {print $1}')
    
    for part in $partitions; do
        dialog --infobox "Unmounting /dev/$part..." 3 40
        umount -f "/dev/$part" 2>/dev/null || true
    done
    
    # Find and disable swap
    local swap_parts=$(lsblk -n -o NAME,FSTYPE "$selected_disk" | grep swap | awk '{print $1}')
    for part in $swap_parts; do
        dialog --infobox "Disabling swap on /dev/$part..." 3 50
        swapoff "/dev/$part" 2>/dev/null || true
    done
    
    # Wipe disk with progress indication
    show_progress "wipefs -a $selected_disk" "Wiping all signatures from $selected_disk..." "Disk wiped successfully"
    
    # Create new partition table
    show_progress "parted -s $selected_disk mklabel gpt" "Creating new GPT partition table..." "GPT partition table created"
}

# Return swap in MiB as half the system RAM
calculate_swap_size() {
    local ram_kB
    ram_kB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local swap_mib=$(( ram_kB / 2 / 1024 ))
    echo "$swap_mib"
}

# Partitioning function
perform_partitioning() {
    local disk="$1"
    local choice="$2"
    local swap_size
    swap_size=$(calculate_swap_size)

    case "$choice" in
        "auto_ext4")
            dialog --infobox "Performing automatic partitioning (ext4) on $disk" 3 60
            local esp=$(get_partition_name "$disk" 1)
            local swp=$(get_partition_name "$disk" 2)
            local root=$(get_partition_name "$disk" 3)

            show_progress "parted -s \"$disk\" mkpart primary fat32 1MiB 513MiB" \
                          "Creating EFI partition..." \
                          "EFI partition created"
            
            show_progress "parted -s \"$disk\" set 1 esp on" \
                          "Setting ESP flag..." \
                          "ESP flag set"
            
            show_progress "parted -s \"$disk\" mkpart primary linux-swap 513MiB \"$((513 + swap_size))MiB\"" \
                          "Creating swap partition..." \
                          "Swap partition created"
            
            show_progress "parted -s \"$disk\" mkpart primary ext4 \"$((513 + swap_size))MiB\" 100%" \
                          "Creating root partition..." \
                          "Root partition created"

            show_progress "partprobe \"$disk\"" "Refreshing partition table..." "Partition table refreshed"
            
            show_progress "wipefs -a \"$esp\"" "Preparing EFI partition..." "EFI partition prepared"
            show_progress "wipefs -a \"$swp\"" "Preparing swap partition..." "Swap partition prepared"
            show_progress "wipefs -a \"$root\"" "Preparing root partition..." "Root partition prepared"

            show_progress "mkfs.fat -F32 -I \"$esp\"" "Formatting EFI partition..." "EFI partition formatted"
            show_progress "mkswap \"$swp\"" "Creating swap..." "Swap created"
            show_progress "swapon \"$swp\"" "Activating swap..." "Swap activated"
            show_progress "mkfs.ext4 -F \"$root\"" "Formatting root partition..." "Root partition formatted"

            show_progress "mount \"$root\" /mnt" "Mounting root partition..." "Root partition mounted"
            show_progress "mkdir -p /mnt/efi" "Creating EFI directory..." "EFI directory created"
            show_progress "mount \"$esp\" /mnt/efi" "Mounting EFI partition..." "EFI partition mounted"
            ;;
        
        "auto_btrfs")
            dialog --infobox "Performing automatic partitioning (BTRFS) on $disk" 3 60
            local esp=$(get_partition_name "$disk" 1)
            local swp=$(get_partition_name "$disk" 2)
            local root=$(get_partition_name "$disk" 3)

            show_progress "parted -s \"$disk\" mkpart primary fat32 1MiB 513MiB" \
                          "Creating EFI partition..." \
                          "EFI partition created"
            
            show_progress "parted -s \"$disk\" set 1 esp on" \
                          "Setting ESP flag..." \
                          "ESP flag set"
            
            show_progress "parted -s \"$disk\" mkpart primary linux-swap 513MiB \"$((513 + swap_size))MiB\"" \
                          "Creating swap partition..." \
                          "Swap partition created"
            
            show_progress "parted -s \"$disk\" mkpart primary btrfs \"$((513 + swap_size))MiB\" 100%" \
                          "Creating root partition..." \
                          "Root partition created"

            show_progress "partprobe \"$disk\"" "Refreshing partition table..." "Partition table refreshed"
            
            show_progress "wipefs -a \"$esp\"" "Preparing EFI partition..." "EFI partition prepared"
            show_progress "wipefs -a \"$swp\"" "Preparing swap partition..." "Swap partition prepared"
            show_progress "wipefs -a \"$root\"" "Preparing root partition..." "Root partition prepared"

            show_progress "mkfs.fat -F32 -I \"$esp\"" "Formatting EFI partition..." "EFI partition formatted"
            show_progress "mkswap \"$swp\"" "Creating swap..." "Swap created"
            show_progress "swapon \"$swp\"" "Activating swap..." "Swap activated"
            show_progress "mkfs.btrfs -f \"$root\"" "Formatting root partition..." "Root partition formatted"

            show_progress "mount \"$root\" /mnt" "Mounting root partition..." "Root partition mounted"
            
            show_progress "btrfs subvolume create /mnt/@" "Creating root subvolume..." "Root subvolume created"
            show_progress "btrfs subvolume create /mnt/@home" "Creating home subvolume..." "Home subvolume created"
            show_progress "btrfs subvolume create /mnt/@log" "Creating log subvolume..." "Log subvolume created"
            show_progress "btrfs subvolume create /mnt/@pkg" "Creating package cache subvolume..." "Package cache subvolume created"
            show_progress "btrfs subvolume create /mnt/@snapshots" "Creating snapshots subvolume..." "Snapshots subvolume created"
            
            show_progress "umount /mnt" "Unmounting root partition..." "Root partition unmounted"

            show_progress "mount -o subvol=@,compress=zstd,noatime \"$root\" /mnt" "Mounting root subvolume..." "Root subvolume mounted"
            show_progress "mkdir -p /mnt/{efi,home,var/log,var/cache/pacman/pkg,.snapshots}" "Creating mount points..." "Mount points created"
            show_progress "mount -o subvol=@home,compress=zstd,noatime \"$root\" /mnt/home" "Mounting home subvolume..." "Home subvolume mounted"
            show_progress "mount -o subvol=@log,compress=zstd,noatime \"$root\" /mnt/var/log" "Mounting log subvolume..." "Log subvolume mounted"
            show_progress "mount -o subvol=@pkg,compress=zstd,noatime \"$root\" /mnt/var/cache/pacman/pkg" "Mounting package cache subvolume..." "Package cache subvolume mounted"
            show_progress "mount -o subvol=@snapshots,compress=zstd,noatime \"$root\" /mnt/.snapshots" "Mounting snapshots subvolume..." "Snapshots subvolume mounted"
            show_progress "mount \"$esp\" /mnt/efi" "Mounting EFI partition..." "EFI partition mounted"
            ;;
        
        "manual")
            dialog --title "Manual Partitioning" --msgbox "You will now be taken to cfdisk for manual partitioning.\n\nYou need to create at minimum:\n- EFI partition (~512MB, type: EFI System)\n- Root partition (rest of disk)\n\nOptionally:\n- Swap partition\n\nAfter partitioning, you will need to format and mount them." 14 65
            cfdisk "$disk"
            
            # Guide user through formatting and mounting partitions
            local partitions=$(lsblk -n -p -o NAME "$disk" | grep -v "^$disk$")
            
            # Create a list of partitions for selection
            local options=""
            for part in $partitions; do
                local size=$(lsblk -n -o SIZE "$part" | tr -d ' ')
                options="$options $part \"$size\" "
            done
            
            # Select EFI partition
            local efi_part=$(dialog --stdout --title "EFI Partition" --menu "Select the EFI partition to format:" 15 60 7 $options)
            if [[ -n "$efi_part" ]]; then
                show_progress "mkfs.fat -F32 -I \"$efi_part\"" "Formatting EFI partition..." "EFI partition formatted"
            else
                dialog --title "Error" --msgbox "EFI partition selection cancelled. Exiting." 5 50
                exit 1
            fi
            
            # Select swap partition if any
            dialog --title "Swap Partition" --yesno "Do you want to create a swap partition?" 6 50
            if [ $? -eq 0 ]; then
                local swap_part=$(dialog --stdout --title "Swap Partition" --menu "Select the swap partition to format:" 15 60 7 $options)
                if [[ -n "$swap_part" ]]; then
                    show_progress "mkswap \"$swap_part\"" "Creating swap..." "Swap created"
                    show_progress "swapon \"$swap_part\"" "Activating swap..." "Swap activated"
                fi
            fi
            
            # Select root partition
            local root_part=$(dialog --stdout --title "Root Partition" --menu "Select the root partition to format:" 15 60 7 $options)
            if [[ -n "$root_part" ]]; then
                local fs_type=$(dialog --stdout --title "Filesystem Type" --menu "Select filesystem for root partition:" 10 50 2 \
                    "ext4" "Extended Filesystem 4" \
                    "btrfs" "B-Tree Filesystem")
                
                if [[ "$fs_type" == "ext4" ]]; then
                    show_progress "mkfs.ext4 -F \"$root_part\"" "Formatting root partition (ext4)..." "Root partition formatted"
                    show_progress "mount \"$root_part\" /mnt" "Mounting root partition..." "Root partition mounted"
                elif [[ "$fs_type" == "btrfs" ]]; then
                    show_progress "mkfs.btrfs -f \"$root_part\"" "Formatting root partition (btrfs)..." "Root partition formatted"
                    
                    dialog --title "BTRFS Subvolumes" --yesno "Do you want to create BTRFS subvolumes?" 6 50
                    if [ $? -eq 0 ]; then
                        show_progress "mount \"$root_part\" /mnt" "Mounting root partition..." "Root partition mounted"
                        show_progress "btrfs subvolume create /mnt/@" "Creating root subvolume..." "Root subvolume created"
                        show_progress "btrfs subvolume create /mnt/@home" "Creating home subvolume..." "Home subvolume created"
                        show_progress "btrfs subvolume create /mnt/@log" "Creating log subvolume..." "Log subvolume created"
                        show_progress "btrfs subvolume create /mnt/@pkg" "Creating package cache subvolume..." "Package cache subvolume created"
                        show_progress "btrfs subvolume create /mnt/@snapshots" "Creating snapshots subvolume..." "Snapshots subvolume created"
                        
                        show_progress "umount /mnt" "Unmounting root partition..." "Root partition unmounted"
                        show_progress "mount -o subvol=@,compress=zstd,noatime \"$root_part\" /mnt" "Mounting root subvolume..." "Root subvolume mounted"
                        show_progress "mkdir -p /mnt/{efi,home,var/log,var/cache/pacman/pkg,.snapshots}" "Creating mount points..." "Mount points created"
                        show_progress "mount -o subvol=@home,compress=zstd,noatime \"$root_part\" /mnt/home" "Mounting home subvolume..." "Home subvolume mounted"
                        show_progress "mount -o subvol=@log,compress=zstd,noatime \"$root_part\" /mnt/var/log" "Mounting log subvolume..." "Log subvolume mounted"
                        show_progress "mount -o subvol=@pkg,compress=zstd,noatime \"$root_part\" /mnt/var/cache/pacman/pkg" "Mounting package cache subvolume..." "Package cache subvolume mounted"
                        show_progress "mount -o subvol=@snapshots,compress=zstd,noatime \"$root_part\" /mnt/.snapshots" "Mounting snapshots subvolume..." "Snapshots subvolume mounted"
                    else
                        show_progress "mount \"$root_part\" /mnt" "Mounting root partition..." "Root partition mounted"
                    fi
                fi
            else
                dialog --title "Error" --msgbox "Root partition selection cancelled. Exiting." 5 50
                exit 1
            fi
            
            # Create and mount EFI directory
            show_progress "mkdir -p /mnt/efi" "Creating EFI directory..." "EFI directory created"
            show_progress "mount \"$efi_part\" /mnt/efi" "Mounting EFI partition..." "EFI partition mounted"
            ;;
    esac
}

# Install base system
install_base_system() {
    if ! mountpoint -q /mnt; then
        dialog --title "Error" --msgbox "No filesystem mounted at /mnt. Cannot install base system." 6 50
        exit 1
    fi

    dialog --title "Shell Selection" --yesno "Do you want to use zsh as your default shell?\n\nSelecting 'No' will use bash as the default shell." 8 60
    local use_zsh=$?

    local base_packages="base linux linux-firmware sudo"
    
    # Add filesystem-specific packages
    if [[ "$partition_choice" == "auto_btrfs" || "$fs_type" == "btrfs" ]]; then
        base_packages="$base_packages btrfs-progs"
    fi
    
    # Add zsh if selected
    if [ $use_zsh -eq 0 ]; then
        base_packages="$base_packages zsh"
    fi
    
    # Install development tools?
    dialog --title "Development Tools" --yesno "Do you want to install development packages?\n(base-devel, git, etc.)" 7 60
    if [ $? -eq 0 ]; then
        base_packages="$base_packages base-devel git"
    fi
    
    dialog --title "Installing Base System" --infobox "Installing base system packages...\nThis may take a while." 5 50
    show_progress "pacstrap -K /mnt $base_packages" "Installing base system packages..." "Base system installed successfully"
    
    # Generate fstab
    show_progress "genfstab -U /mnt >> /mnt/etc/fstab" "Generating fstab..." "fstab generated successfully"
}

# Configure pacman for parallel downloads
configure_pacman_parallel() {
    # Count CPU cores for parallel downloads
    local cores=$(nproc)
    local parallel_downloads=$((cores > 5 ? 5 : cores))
    
    show_progress "sed -i \"s/#ParallelDownloads = 5/ParallelDownloads = $parallel_downloads/\" /mnt/etc/pacman.conf" \
                  "Configuring pacman for parallel downloads..." \
                  "Pacman configured for parallel downloads"
    
    # Enable color output
    show_progress "sed -i \"s/#Color/Color/\" /mnt/etc/pacman.conf" \
                  "Enabling pacman color output..." \
                  "Pacman color output enabled"
    
    # Enable pacman progress bar
    show_progress "sed -i \"s/#VerbosePkgLists/VerbosePkgLists/\" /mnt/etc/pacman.conf" \
                  "Enabling verbose package lists..." \
                  "Verbose package lists enabled"
}

# Configure locale settings
configure_locales() {
    # Get user's country code from IP (fallback to US)
    local country_code=$(curl -s https://ipapi.co/country_code || echo "US")
    
    # Map common country codes to locales
    local default_locale="en_US.UTF-8"
    case "$country_code" in
        "DE") default_locale="de_DE.UTF-8" ;;
        "FR") default_locale="fr_FR.UTF-8" ;;
        "ES") default_locale="es_ES.UTF-8" ;;
        "IT") default_locale="it_IT.UTF-8" ;;
        "JP") default_locale="ja_JP.UTF-8" ;;
    esac
    
    # Common locales to offer
    local locales=(
        "en_US.UTF-8 UTF-8"
        "en_GB.UTF-8 UTF-8"
        "de_DE.UTF-8 UTF-8"
        "fr_FR.UTF-8 UTF-8"
        "es_ES.UTF-8 UTF-8"
        "it_IT.UTF-8 UTF-8"
        "ja_JP.UTF-8 UTF-8"
        "zh_CN.UTF-8 UTF-8"
    )
    
    # Build menu items
    local options=""
    local default_item=""
    for locale in "${locales[@]}"; do
        if [[ "$locale" == "$default_locale UTF-8" ]]; then
            default_item="$locale"
        fi
        options="$options $locale $locale "
    done
    
    # Show menu with default option
    selected_locale=$(dialog --stdout --default-item "$default_locale UTF-8" \
                     --title "Locale Selection" --menu "Select your system locale:" 15 70 8 $options)
    
    # If user cancelled, use default
    if [[ -z "$selected_locale" ]]; then
        selected_locale="$default_locale UTF-8"
    fi
    
    # Generate the selected locale
    show_progress "echo \"$selected_locale\" > /mnt/etc/locale.gen" \
                  "Configuring locale..." \
                  "Locale configured"
                  
    show_progress "arch-chroot /mnt locale-gen" \
                  "Generating locale..." \
                  "Locale generated"
                  
    show_progress "echo \"LANG=$(echo \"$selected_locale\" | awk '{print $1}')\" > /mnt/etc/locale.conf" \
                  "Setting system language..." \
                  "System language set"
}

# Configure timezone
configure_timezone() {
    # Try to get timezone from IP
    local timezone=$(curl -s https://ipapi.co/timezone)
    
    if [[ -z "$timezone" || ! -f "/usr/share/zoneinfo/$timezone" ]]; then
        # If auto-detection fails, offer regions
        local regions=$(find /usr/share/zoneinfo -type d -mindepth 1 -maxdepth 1 | sort | sed 's|/usr/share/zoneinfo/||g')
        
        local region_options=""
        for region in $regions; do
            # Skip some special folders
            if [[ "$region" != "posix" && "$region" != "right" && "$region" != "Etc" ]]; then
                region_options="$region_options $region $region "
            fi
        done
        
        local selected_region=$(dialog --stdout --title "Timezone Region" --menu "Select your timezone region:" 20 60 12 $region_options)
        
        if [[ -z "$selected_region" ]]; then
            selected_region="Etc"
        fi
        
        # Get cities for the selected region
        local cities=$(find "/usr/share/zoneinfo/$selected_region" -type f | sort | sed "s|/usr/share/zoneinfo/$selected_region/||g")
        
        local city_options=""
        for city in $cities; do
            city_options="$city_options $city $city "
        done
        
        local selected_city=$(dialog --stdout --title "Timezone City" --menu "Select your timezone city:" 20 60 12 $city_options)
        
        if [[ -n "$selected_city" ]]; then
            timezone="$selected_region/$selected_city"
        else
            timezone="UTC"
        fi
    fi
    
    show_progress "arch-chroot /mnt ln -sf \"/usr/share/zoneinfo/$timezone\" /etc/localtime" \
                  "Setting timezone to $timezone..." \
                  "Timezone set to $timezone"
                  
    show_progress "arch-chroot /mnt hwclock --systohc" \
                  "Setting hardware clock..." \
                  "Hardware clock set"
}

# Configure hostname
configure_hostname() {
    local hostname=$(dialog --stdout --title "Hostname" --inputbox "Enter your desired hostname:" 8 50)
    
    if [[ -z "$hostname" ]]; then
        hostname="archlinux"
    fi
    
    show_progress "echo \"$hostname\" > /mnt/etc/hostname" \
                  "Setting hostname..." \
                  "Hostname set"
                  
    # Configure hosts file
    show_progress "echo -e \"127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t$hostname.localdomain $hostname\" > /mnt/etc/hosts" \
                  "Configuring hosts file..." \
                  "Hosts file configured"
}

# Hardware detection and driver installation
detect_hardware() {
    dialog --infobox "Detecting hardware..." 3 30
    
    # Check for NVIDIA GPU
    if lspci | grep -i nvidia &>/dev/null; then
        dialog --title "NVIDIA GPU Detected" --yesno "NVIDIA graphics card detected.\n\nInstall NVIDIA DKMS drivers for Wayland?" 8 60
        if [ $? -eq 0 ]; then
            show_progress "arch-chroot /mnt pacman -S --noconfirm linux-headers nvidia-dkms nvidia-utils lib32-nvidia-utils" \
                          "Installing NVIDIA DKMS drivers..." \
                          "NVIDIA drivers installed successfully"
            
            # Add kernel parameters for better Wayland support
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=".*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 nowatchdog nvidia_drm.modeset=1"/' /mnt/etc/default/grub
        fi
    fi
    
    # Check for AMD GPU
    if lspci | grep -i amd &>/dev/null; then
        dialog --title "AMD GPU Detected" --yesno "AMD graphics card detected.\n\nInstall open-source drivers?" 8 60
        if [ $? -eq 0 ]; then
            show_progress "arch-chroot /mnt pacman -S --noconfirm mesa lib32-mesa" \
                          "Installing AMD drivers..." \
                          "AMD drivers installed successfully"
        fi
    fi
    
    # CPU microcode updates
    if grep -q "Intel" /proc/cpuinfo; then
        show_progress "arch-chroot /mnt pacman -S --noconfirm intel-ucode" \
                      "Installing Intel microcode updates..." \
                      "Intel microcode installed successfully"
    elif grep -q "AMD" /proc/cpuinfo; then
        show_progress "arch-chroot /mnt pacman -S --noconfirm amd-ucode" \
                      "Installing AMD microcode updates..." \
                      "AMD microcode installed successfully"
    fi
}

# Network configuration
setup_network() {
    dialog --title "Network Configuration" --yesno "Install NetworkManager for network connectivity?" 6 60
    
    if [ $? -eq 0 ]; then
        show_progress "arch-chroot /mnt pacman -S --noconfirm networkmanager" \
                      "Installing NetworkManager..." \
                      "NetworkManager installed successfully"
        
        show_progress "arch-chroot /mnt systemctl enable NetworkManager.service" \
                      "Enabling NetworkManager service..." \
                      "NetworkManager service enabled"
    else
        dialog --title "Warning" --msgbox "No network manager installed. You will need to configure networking manually after installation." 7 60
    fi
}

# Configure boot parameters
configure_boot_parameters() {
    # Add proper parameters to kernel cmdline for better performance
    show_progress "sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\".*\"/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet loglevel=3 nowatchdog\"/' /mnt/etc/default/grub" \
                  "Configuring kernel parameters..." \
                  "Kernel parameters configured"
    
    # Update mkinitcpio.conf for better hooks based on filesystem
    if [[ "$partition_choice" == "auto_btrfs" || "$fs_type" == "btrfs" ]]; then
        show_progress "sed -i 's/HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems btrfs)/' /mnt/etc/mkinitcpio.conf" \
                      "Configuring initramfs hooks for BTRFS..." \
                      "Initramfs hooks configured"
    else
        show_progress "sed -i 's/HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/' /mnt/etc/mkinitcpio.conf" \
                      "Configuring initramfs hooks..." \
                      "Initramfs hooks configured"
    fi
    
    show_progress "arch-chroot /mnt mkinitcpio -P" \
                  "Generating initramfs..." \
                  "Initramfs generated"
}

# Install bootloader
install_bootloader() {
    dialog --title "Bootloader Installation" --infobox "Installing GRUB bootloader..." 3 40
    
    show_progress "arch-chroot /mnt pacman -S --noconfirm grub efibootmgr" \
                  "Installing GRUB and EFI boot manager..." \
                  "GRUB and EFI boot manager installed"
                  
    show_progress "arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB" \
                  "Installing GRUB bootloader..." \
                  "GRUB bootloader installed"
                  
    show_progress "arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg" \
                  "Generating GRUB configuration..." \
                  "GRUB configuration generated"
}

# Create user account
create_user_account() {
    local username
    local -a additional_groups=("wheel")
    
    while true; do
        username=$(dialog --stdout --title "User Account" --inputbox "Enter username (lowercase letters, numbers, or underscore, 3-32 chars):" 8 60)
        
        if [[ -z "$username" ]]; then
            dialog --title "Cancelled" --msgbox "User account creation cancelled. Root login will be required." 5 50
            return 1
        fi
        
        if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{2,31}$ ]]; then
            dialog --title "Invalid Username" --msgbox "ERROR: Invalid username format. Please try again." 5 50
            continue
        fi
        
        local reserved_names=("root" "daemon" "bin" "sys" "sync" "games" "man" "lp" "mail" "news" "uucp" "proxy" "www-data" "backup" "list" "irc" "gnats" "nobody" "systemd-network" "systemd-resolve" "messagebus" "systemd-timesync" "polkitd")
        if [[ " ${reserved_names[@]} " =~ " ${username} " ]]; then
            dialog --title "Reserved Username" --msgbox "ERROR: Username '$username' is reserved. Please choose another." 5 60
            continue
        fi
        
        break
    done
    
    show_progress "arch-chroot /mnt useradd -m -G \"$(IFS=,; echo "${additional_groups[*]}")\" -s /bin/bash \"$username\"" \
                  "Creating user account..." \
                  "User account created"
    
    dialog --title "User Password" --msgbox "Set password for user $username.\nYou will be prompted to enter it twice." 7 50
    
    # No progress indicator for password as it requires user input
    arch-chroot /mnt passwd "$username"
    
    # Configure sudo access
    show_progress "arch-chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers" \
                  "Configuring sudo access..." \
                  "Sudo access configured"
                  
    show_progress "arch-chroot /mnt visudo -c" \
                  "Validating sudoers configuration..." \
                  "Sudoers configuration validated"
    
    return 0
}

setup_user_environment() {
    local username="$1"
    
    # Copy the actual ZSH config from the Arch live ISO
    show_progress "mkdir -p /mnt/home/$username/.zsh" \
                  "Creating ZSH directory structure..." \
                  "ZSH directory created"
    
    # Make sure ZSH is installed in the target system
    show_progress "arch-chroot /mnt pacman -S --noconfirm zsh" \
                  "Installing ZSH shell..." \
                  "ZSH shell installed"
    
    # Copy all the good shit from the ISO's ZSH setup
    show_progress "cp /etc/zsh/* /mnt/etc/zsh/ 2>/dev/null || true" \
                  "Copying system ZSH config..." \
                  "System ZSH config copied"
                  
    show_progress "cp ~/.zshrc /mnt/home/$username/ 2>/dev/null || cp /etc/skel/.zshrc /mnt/home/$username/ 2>/dev/null || true" \
                  "Copying ZSH user config..." \
                  "ZSH user config copied"
                  
    # Copy the awesome prompt, aliases and settings
    show_progress "cp ~/.zprofile /mnt/home/$username/ 2>/dev/null || true" \
                  "Copying ZSH profile..." \
                  "ZSH profile copied"
                  
    # If those copies failed, let's make sure there's at least a basic config
    show_progress "[ -f /mnt/home/$username/.zshrc ] || echo 'source /etc/zsh/zshrc' > /mnt/home/$username/.zshrc" \
                  "Ensuring ZSH config exists..." \
                  "ZSH config confirmed"
    
    # Set ZSH as default shell for the user
    show_progress "arch-chroot /mnt chsh -s /bin/zsh $username" \
                  "Setting ZSH as default shell..." \
                  "Default shell set to ZSH"
                  
    # Make sure permissions are right
    show_progress "arch-chroot /mnt chown -R $username:$username /home/$username" \
                  "Setting correct file ownership..." \
                  "File ownership set"
}

# Install common software
install_common_software() {
    # Ask if user wants additional software at all
    dialog --title "Additional Software" --yesno "Arch Linux base system is now installed.\n\nWould you like to install any additional software packages?" 8 60
    
    if [ $? -ne 0 ]; then
        return 0
    fi
    
    # Let user select categories
    selected_cats=$(dialog --stdout --title "Software Categories" --checklist "Select software categories to install:" 15 60 5 \
        "basic" "Basic utilities (vim, git, htop)" OFF \
        "dev" "Development tools (gcc, make, python)" OFF \
        "media" "Multimedia support (codecs, players)" OFF \
        "office" "Office applications (libreoffice)" OFF \
        "browser" "Web browsers" OFF)
    
    if [[ -z "$selected_cats" ]]; then
        return 0
    fi
    
    # Install selected categories
    for cat in $selected_cats; do
        case "$cat" in
            "basic")
                show_progress "arch-chroot /mnt pacman -S --noconfirm vim git htop neofetch" \
                              "Installing basic utilities..." \
                              "Basic utilities installed successfully"
                ;;
            "dev")
                show_progress "arch-chroot /mnt pacman -S --noconfirm base-devel gcc cmake make python python-pip" \
                              "Installing development tools..." \
                              "Development tools installed successfully"
                ;;
            "media")
                show_progress "arch-chroot /mnt pacman -S --noconfirm mpv gst-plugins-base gst-plugins-good" \
                              "Installing multimedia support..." \
                              "Multimedia support installed successfully"
                ;;
            "office")
                show_progress "arch-chroot /mnt pacman -S --noconfirm libreoffice-fresh" \
                              "Installing office applications..." \
                              "Office applications installed successfully"
                ;;
            "browser")
                browser=$(dialog --stdout --title "Web Browser" --menu "Select a web browser to install:" 12 60 4 \
                    "firefox" "Mozilla Firefox" \
                    "chromium" "Chromium" \
                    "qutebrowser" "Keyboard-driven browser" \
                    "none" "Skip browser installation")
                
                if [ "$browser" != "none" ]; then
                    show_progress "arch-chroot /mnt pacman -S --noconfirm $browser" \
                                  "Installing $browser..." \
                                  "$browser installed successfully"
                fi
                ;;
        esac
    done
}

# Setup root password
setup_root_password() {
    dialog --title "Root Password" --msgbox "Set password for the root account.\nYou will be prompted to enter it twice." 7 50
    arch-chroot /mnt passwd
}

# Main function
main() {
    # Welcome screen
    dialog --title "Arch Linux TUI Installer" \
           --msgbox "Welcome to the Arch Linux installer!\n\nThis will guide you through a minimal Arch Linux installation that you can customize to your needs." 10 60
    
    # Verify environment
    check_internet
    check_uefi
    
    # Select disk and partition
    select_disk
    wipe_partitions
    select_partition_scheme
    perform_partitioning "$selected_disk" "$partition_choice"
    
    # Configure and install base system
    install_base_system
    configure_pacman_parallel
    
    # Configure system
    configure_locales
    configure_timezone
    configure_hostname
    
    # Hardware detection and drivers
    detect_hardware
    
    # Network configuration - wired only
    setup_network
    
    # Bootloader setup
    configure_boot_parameters
    install_bootloader
    
    # User setup
    setup_root_password
    if create_user_account; then
        setup_user_environment "$username"
    fi
    
    # Optional software
    install_common_software
    
    # Final message
    dialog --title "Installation Complete" \
           --msgbox "Arch Linux has been successfully installed!\n\nThe system is ready to use. You can now reboot your system." 10 60
    
    # Unmount everything
    dialog --infobox "Unmounting partitions..." 3 40
    umount -R /mnt
    
    dialog --title "Installation Complete" \
           --yesno "Installation complete! Would you like to reboot now?" 6 50
    
    if [ $? -eq 0 ]; then
        dialog --infobox "Rebooting in 5 seconds..." 3 30
        sleep 5
        reboot
    else
        dialog --msgbox "You can reboot when ready by typing 'reboot'." 5 40
    fi
}

# Validate boot media before proceeding
check_boot_media "$@"

# Run main function
main
