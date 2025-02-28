#!/bin/bash
# Filesystem setup and configuration module

# Function to create ext4 filesystem
create_ext4_filesystem() {
    local device=$1
    local mount_point=$2
    
    log "Creating ext4 filesystem on $device..."
    mkfs.ext4 -F "$device"
    
    mkdir -p "$mount_point"
    mount "$device" "$mount_point"
    
    log "Mounted ext4 filesystem from $device to $mount_point"
}

# Function to create and set up BTRFS with custom subvolume layout
create_btrfs_filesystem() {
    local device=$1
    local efi_partition=$2
    
    log "Creating BTRFS filesystem on $device..."
    mkfs.btrfs -f "$device"
    
    log "Mounting BTRFS root for subvolume creation..."
    mkdir -p /mnt
    mount "$device" /mnt
    
    log "Creating BTRFS subvolumes..."
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@pkg
    btrfs subvolume create /mnt/@log
    
    log "Unmounting root BTRFS filesystem..."
    umount /mnt
    
    # Custom mount options as specified
    local mount_opts="noatime,discard=async,compress=zstd,space_cache=v2"
    
    log "Mounting BTRFS subvolumes with options: $mount_opts"
    # Mount @ subvolume as root
    mount -o "$mount_opts,subvol=@" "$device" /mnt
    
    # Create mount points for other subvolumes
    mkdir -p /mnt/{efi,home,var/log,var/cache/pacman/pkg}
    
    # Mount other subvolumes with same options
    mount -o "$mount_opts,subvol=@home" "$device" /mnt/home
    mount -o "$mount_opts,subvol=@log" "$device" /mnt/var/log
    mount -o "$mount_opts,subvol=@pkg" "$device" /mnt/var/cache/pacman/pkg
    
    # Mount EFI partition if provided and in UEFI mode
    if [[ -n "$efi_partition" && "$UEFI_MODE" -eq 1 ]]; then
        log "Mounting EFI partition at /mnt/efi..."
        mkdir -p /mnt/efi
        mount "$efi_partition" /mnt/efi
    fi
    
    log "BTRFS filesystem setup completed successfully"
}

# Function to create swap file on BTRFS using the recommended mkswapfile command
create_btrfs_swapfile() {
    local size=$1  # Size in MB
    local device=$2  # Root device
    
    if [[ $size -le 0 ]]; then
        log "No swap file requested"
        return 0
    fi
    
    # Convert MB to GB for nicer display (rounded up)
    local size_gb=$(( (size + 1023) / 1024 ))
    log "Creating ${size_gb}GB swap file..."
    
    # Create a dedicated subvolume for swap (following our @ naming convention)
    btrfs subvolume create /mnt/@swap
    mkdir -p /mnt/swap
    mount -o noatime,discard=async,compress=no,space_cache=v2,subvol=@swap "$device" /mnt/swap
    
    # Create and format the swap file using BTRFS's specialized command if available
    if command -v btrfs &>/dev/null && btrfs filesystem mkswapfile --help &>/dev/null 2>/dev/null; then
        log "Using btrfs mkswapfile command"
        btrfs filesystem mkswapfile --size "${size_gb}G" /mnt/swap/swapfile
    else
        log "Using traditional swap file creation method"
        # Create swap file with NOCOW attribute 
        truncate -s 0 /mnt/swap/swapfile
        chattr +C /mnt/swap/swapfile  # Disable COW
        dd if=/dev/zero of=/mnt/swap/swapfile bs=1M count="$size" status=progress
        chmod 600 /mnt/swap/swapfile
        mkswap /mnt/swap/swapfile
    fi
    
    # Activate the swap file
    swapon /mnt/swap/swapfile
    
    # Add to fstab for persistence
    echo "# Swap file" >> /mnt/etc/fstab
    echo "/swap/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
    
    log "Swap file created and activated"
}

# Function to generate fstab
generate_fstab() {
    log "Generating fstab..."
    
    mkdir -p /mnt/etc
    
    # Generate fstab file using UUIDs and filter out subvolid entries for BTRFS
    genfstab -U /mnt | sed 's/,subvolid=[0-9]*//g' > /mnt/etc/fstab
    
    # Verify fstab was created successfully
    if [[ ! -s /mnt/etc/fstab ]]; then
        error "Failed to generate fstab"
    fi
    
    log "Fstab generated successfully"
}

# Configure filesystem based on selected type
setup_filesystem() {
    local disk=$1
    local fs_type=$2
    local efi_partition="${3:-}"
    
    log "Setting up $fs_type filesystem on $disk..."
    
    case "$fs_type" in
        btrfs)
            create_btrfs_filesystem "$disk" "$efi_partition"
            ;;
        ext4)
            create_ext4_filesystem "$disk" "/mnt"
            if [[ -n "$efi_partition" && "$UEFI_MODE" -eq 1 ]]; then
                mkdir -p /mnt/efi
                mount "$efi_partition" /mnt/efi
            fi
            ;;
        *)
            error "Unsupported filesystem type: $fs_type"
            ;;
    esac
    
    # Generate fstab after filesystem is set up
    generate_fstab
}
