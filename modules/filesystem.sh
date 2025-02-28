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
    return 0
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
    
    # Mount EFI partition if provided
    if [[ -n "$efi_partition" ]]; then
        log "Mounting EFI partition at /mnt/efi..."
        mkdir -p /mnt/efi
        mount "$efi_partition" /mnt/efi
    fi
    
    log "BTRFS filesystem setup completed successfully"
    return 0
}

# Function to create swap file on BTRFS
create_btrfs_swapfile() {
    local size=$1  # Size in MB
    local device=${2:-""}  # Root device
    
    if [[ $size -le 0 ]]; then
        log "No swap file requested"
        return 0
    fi
    
    log "Creating ${size}MB swap file..."
    
    # Create swap file using the recommended method for BTRFS
    mkdir -p /mnt/var/swap
    
    # Create swap file with NOCOW attribute to prevent corruption
    truncate -s 0 /mnt/var/swap/swapfile
    chattr +C /mnt/var/swap/swapfile  # Disable COW
    dd if=/dev/zero of=/mnt/var/swap/swapfile bs=1M count="$size" status=progress
    chmod 600 /mnt/var/swap/swapfile
    mkswap /mnt/var/swap/swapfile
    swapon /mnt/var/swap/swapfile
    
    # Add to fstab
    echo "# Swap file" >> /mnt/etc/fstab
    echo "/var/swap/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
    
    log "Swap file created and activated"
    return 0
}

# Function to generate fstab - modified to properly include swap
generate_fstab() {
    log "Generating fstab..."
    
    if [[ ! -d /mnt/etc ]]; then
        mkdir -p /mnt/etc
    fi
    
    # Use genfstab to create fstab file but filter out subvolid entries
    if command -v genfstab &>/dev/null; then
        # Generate fstab and remove subvolid entries
        genfstab -U /mnt | sed 's/,subvolid=[0-9]*//g' > /mnt/etc/fstab
        log "Fstab generated with subvolid entries removed"
    else
        # Fallback for test mode or if genfstab is not available
        log "Creating manual fstab in test mode"
        cat > /mnt/etc/fstab <<EOF
# /etc/fstab: static file system information
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=mock-uuid-root / btrfs rw,noatime,discard=async,compress=zstd,space_cache=v2,subvol=@ 0 0
UUID=mock-uuid-root /home btrfs rw,noatime,discard=async,compress=zstd,space_cache=v2,subvol=@home 0 0
UUID=mock-uuid-root /var/cache/pacman/pkg btrfs rw,noatime,discard=async,compress=zstd,space_cache=v2,subvol=@pkg 0 0
UUID=mock-uuid-root /var/log btrfs rw,noatime,discard=async,compress=zstd,space_cache=v2,subvol=@log 0 0
UUID=mock-uuid-efi /efi vfat rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro 0 2
EOF
    fi
    
    log "Fstab generated successfully"
    return 0
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
            if [[ -n "$efi_partition" ]]; then
                mkdir -p /mnt/efi
                mount "$efi_partition" /mnt/efi
            fi
            ;;
        *)
            error "Unsupported filesystem type: $fs_type"
            ;;
    esac
    
    return 0
}
