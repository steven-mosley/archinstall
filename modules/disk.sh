#!/bin/bash
# Disk partitioning and setup module

# Function to create GPT partition table and partitions for UEFI
create_uefi_partitions() {
    local disk=$1
    local efi_size=${2:-512}  # Default EFI size in MiB
    
    log "Creating GPT partition table on $disk..."
    sgdisk --zap-all "$disk"
    
    log "Creating EFI system partition (${efi_size}MiB)..."
    sgdisk --new=1:0:+"$efi_size"M --typecode=1:ef00 --change-name=1:"EFI System" "$disk"
    
    log "Creating root partition with remaining space..."
    sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:"Linux Root" "$disk"
    
    # Make sure kernel rereads partition table
    partprobe "$disk"
    
    # Return partition names (EFI, Root)
    echo "${disk}1 ${disk}2"
}

# Function to create MBR partition table and partitions for BIOS
create_bios_partitions() {
    local disk=$1
    
    log "Creating MBR partition table on $disk..."
    parted -s "$disk" mklabel msdos
    
    log "Creating BIOS boot partition..."
    parted -s "$disk" mkpart primary 1MiB 2MiB
    parted -s "$disk" set 1 bios_grub on
    
    log "Creating root partition with remaining space..."
    parted -s "$disk" mkpart primary 2MiB 100%
    
    # Make sure kernel rereads partition table
    partprobe "$disk"
    
    # Return partition names (Boot, Root)
    echo "${disk}1 ${disk}2"
}

# Function to format partitions
format_partitions() {
    local efi_partition=$1
    local root_partition=$2
    local filesystem=${3:-btrfs}  # Default filesystem is btrfs
    local swap_size_mb=${4:-0}
    
    # Format EFI partition if UEFI mode
    if [[ "$UEFI_MODE" -eq 1 && -n "$efi_partition" ]]; then
        log "Formatting EFI partition as FAT32..."
        mkfs.fat -F32 "$efi_partition"
    fi
    
    log "Formatting root partition as $filesystem..."
    case "$filesystem" in
        btrfs)
            setup_filesystem "$root_partition" "btrfs" "$efi_partition"
            
            # Create swap file if needed
            if [[ $swap_size_mb -gt 0 ]]; then
                log "Creating $swap_size_mb MB BTRFS swap file..."
                create_btrfs_swapfile "$swap_size_mb" "$root_partition"
            fi
            ;;
        ext4)
            setup_filesystem "$root_partition" "ext4" "$efi_partition"
            
            # Create swap file for ext4
            if [[ $swap_size_mb -gt 0 ]]; then
                log "Creating $swap_size_mb MB ext4 swap file..."
                create_ext4_swapfile "$swap_size_mb"
            fi
            ;;
        *)
            error "Unsupported filesystem: $filesystem"
            ;;
    esac
}

# Create swap file for ext4
create_ext4_swapfile() {
    local size=$1  # Size in MB
    
    if [[ $size -le 0 ]]; then
        log "No swap file requested"
        return 0
    fi
    
    log "Creating ${size}MB swap file..."
    
    # Create swap file
    dd if=/dev/zero of=/mnt/swapfile bs=1M count="$size" status=progress
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile
    
    # Add to fstab for persistence
    echo "# Swap file" >> /mnt/etc/fstab
    echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
    
    log "Swap file created and activated"
}

# Function to perform partitioning based on selected scheme
perform_partitioning() {
    log "Partitioning disk $selected_disk..."
    
    local efi_partition
    local boot_partition
    local root_partition
    local filesystem
    
    # Determine swap size
    local swap_size_mb=$(determine_swap_size)
    log "Selected swap size: $swap_size_mb MB"
    
    # Create partitions based on boot mode and scheme
    if [[ "$UEFI_MODE" -eq 1 ]]; then
        log "Creating partitions for UEFI boot..."
        read -r efi_partition root_partition < <(create_uefi_partitions "$selected_disk")
    else
        log "Creating partitions for BIOS boot..."
        read -r boot_partition root_partition < <(create_bios_partitions "$selected_disk")
        efi_partition=""
    fi
    
    # Set filesystem type based on user choice
    case "$partition_choice" in
        1) # BTRFS with subvolumes
            log "Setting up BTRFS with subvolumes..."
            filesystem="btrfs"
            # Install btrfs-progs if needed
            pacman -S --noconfirm --needed btrfs-progs
            ;;
        2) # Simple ext4
            log "Setting up ext4 filesystem..."
            filesystem="ext4"
            ;;
        3) # Custom partitioning - prompt for choices
            log "Custom partitioning selected"
            echo "Select filesystem type:"
            echo "1. BTRFS with subvolumes"
            echo "2. EXT4"
            read -r -p "Enter choice (1-2): " fs_choice
            
            if [[ "$fs_choice" == "1" ]]; then
                filesystem="btrfs"
                pacman -S --noconfirm --needed btrfs-progs
            else
                filesystem="ext4"
            fi
            ;;
    esac
    
    # Format the partitions
    format_partitions "$efi_partition" "$root_partition" "$filesystem" "$swap_size_mb"
    
    log "Partitioning completed"
}

# Function to determine system RAM
get_system_ram() {
    # Get total memory in KB and convert to GB
    local mem_kb
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$(( mem_kb / 1024 / 1024 ))
    
    # Default to 8GB if we can't determine
    if [[ $mem_gb -lt 1 ]]; then
        mem_gb=8
    fi
    
    echo "$mem_gb"
}

# Function to determine swap size based on user preference
determine_swap_size() {
    local ram_gb=$(get_system_ram)
    
    # Calculate size options in GB first for display
    local quarter_gb=$(( ram_gb / 4 ))
    local half_gb=$(( ram_gb / 2 ))
    local full_gb=$ram_gb
    
    # Ensure minimum sizes 
    [[ $quarter_gb -lt 1 ]] && quarter_gb=1
    [[ $half_gb -lt 2 ]] && half_gb=2
    
    echo "System RAM: $ram_gb GB"
    echo "Recommended swap size options:"
    echo "1. Quarter RAM size ($quarter_gb GB)"
    echo "2. Half RAM size ($half_gb GB) - Recommended for most systems"
    echo "3. Full RAM size ($full_gb GB) - Recommended if hibernation is needed"
    echo "4. No swap"
    
    local choice
    read -r -p "Select swap size option (1-4): " choice
    
    # Calculate swap size in MB (1 GB = 1024 MB)
    local swap_mb=0
    case "$choice" in
        1) swap_mb=$((quarter_gb * 1024)) ;;
        2) swap_mb=$((half_gb * 1024)) ;;
        3) swap_mb=$((full_gb * 1024)) ;;
        4) swap_mb=0 ;;
        *) 
            log "Invalid choice, defaulting to option 2 (half RAM)"
            swap_mb=$((half_gb * 1024))
            ;;
    esac
    
    # Ensure a minimum size of 512MB for non-zero swap
    if [[ $swap_mb -gt 0 && $swap_mb -lt 512 ]]; then
        swap_mb=512
    fi
    
    log "Selected swap size: $swap_mb MB"
    echo "$swap_mb"
}

# Function to create disk selection menu
create_disk_menu() {
    log "Scanning available disks..."
    
    # Get actual disk names
    local disks=()
    while IFS= read -r disk; do
        if [[ -n "$disk" && "$disk" != "NAME" && "$disk" != "loop"* ]]; then
            disks+=("$disk")
        fi
    done < <(lsblk -d -o NAME -n)
    
    if [[ ${#disks[@]} -eq 0 ]]; then
        error "No disks found"
    fi
    
    echo "Available disks:"
    for i in "${!disks[@]}"; do
        size=$(lsblk -dn -o SIZE /dev/"${disks[i]}")
        model=$(lsblk -dn -o MODEL /dev/"${disks[i]}")
        echo "$((i+1)). /dev/${disks[i]} - $size - $model"
    done
    
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
}

# Function to wipe partitions
wipe_partitions() {
    if prompt "WARNING: This will erase ALL data on $selected_disk. Continue?"; then
        log "Wiping partition table on $selected_disk..."
        wipefs -a "$selected_disk"
        log "Partition table wiped"
    else
        error "Installation canceled"
    fi
}

# Function to present partitioning options
create_partition_menu() {
    echo "Partitioning schemes:"
    echo "1. BTRFS with subvolumes (root, home, packages, logs)"
    echo "2. Simple ext4 filesystem"
    echo "3. Custom partitioning"
    
    read -r -p "Select a partitioning scheme (1-3): " partition_choice
    
    if ! [[ "$partition_choice" =~ ^[1-3]$ ]]; then
        error "Invalid selection"
    fi
    
    log "Selected partitioning scheme: $partition_choice"
}
