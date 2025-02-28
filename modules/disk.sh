#!/bin/bash
# Disk partitioning and setup module

# Function to create GPT partition table and partitions
create_gpt_partitions() {
    local disk=$1
    local efi_size=${2:-512}  # Default EFI size in MiB
    local swap_size_mb=${3:-0}  # Swap size in MiB, 0 means no swap
    local filesystem=${4:-btrfs}
    
    log "Creating GPT partition table on $disk..."
    sgdisk --zap-all "$disk"
    
    log "Creating EFI system partition (${efi_size}MiB)..."
    sgdisk --new=1:0:+"$efi_size"M --typecode=1:ef00 --change-name=1:"EFI System" "$disk"
    
    # Create swap partition if needed and not using BTRFS (BTRFS will use a file)
    if [[ $swap_size_mb -gt 0 && "$filesystem" != "btrfs" ]]; then
        log "Creating swap partition (${swap_size_mb}MiB)..."
        sgdisk --new=2:0:+"$swap_size_mb"M --typecode=2:8200 --change-name=2:"Linux Swap" "$disk"
        
        log "Creating root partition with remaining space..."
        sgdisk --new=3:0:0 --typecode=3:8300 --change-name=3:"Linux Root" "$disk"
        
        # Return partition names (EFI, Swap, Root)
        echo "${disk}1 ${disk}2 ${disk}3"
    else
        log "Creating root partition with remaining space..."
        sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:"Linux Root" "$disk"
        
        # Return partition names (EFI, Root)
        echo "${disk}1 ${disk}2"
    fi
    
    # Make sure kernel rereads partition table
    partprobe "$disk"
    return 0
}

# Function to format partitions
format_partitions() {
    local efi_partition=$1
    local root_partition=$2
    local filesystem=${3:-btrfs}  # Default filesystem is btrfs
    local swap_partition=${4:-""}
    local swap_size_mb=${5:-0}
    
    log "Formatting EFI partition as FAT32..."
    mkfs.fat -F32 "$efi_partition"
    
    # Format swap partition if it exists
    if [[ -n "$swap_partition" && "$swap_partition" != "$root_partition" ]]; then
        log "Formatting swap partition..."
        mkswap "$swap_partition"
        swapon "$swap_partition"
    fi
    
    log "Formatting root partition as $filesystem..."
    case "$filesystem" in
        btrfs)
            setup_filesystem "$root_partition" "btrfs" "$efi_partition"
            
            # Create swap file if needed
            if [[ $swap_size_mb -gt 0 ]]; then
                log "Creating $swap_size_mb MB BTRFS swap file..."
                create_btrfs_swapfile "$swap_size_mb"
            fi
            ;;
        ext4)
            setup_filesystem "$root_partition" "ext4" "$efi_partition"
            ;;
        *)
            error "Unsupported filesystem: $filesystem"
            ;;
    esac
    
    return 0
}

# Function to perform partitioning based on selected scheme
perform_partitioning() {
    log "Partitioning disk $selected_disk..."
    
    local efi_partition
    local root_partition
    local swap_partition
    local filesystem
    
    # Determine swap size
    local swap_size_mb=$(determine_swap_size)
    log "Selected swap size: $swap_size_mb MB"
    
    case "$partition_choice" in
        1) # BTRFS with subvolumes
            log "Creating partitions with BTRFS subvolumes..."
            read -r efi_partition root_partition < <(create_gpt_partitions "$selected_disk" "512" "$swap_size_mb" "btrfs")
            filesystem="btrfs"
            ;;
        2) # Simple ext4
            log "Creating simple partitions with ext4..."
            if [[ $swap_size_mb -gt 0 ]]; then
                read -r efi_partition swap_partition root_partition < <(create_gpt_partitions "$selected_disk" "512" "$swap_size_mb" "ext4")
            else
                read -r efi_partition root_partition < <(create_gpt_partitions "$selected_disk" "512" "0" "ext4")
            fi
            filesystem="ext4"
            ;;
        3) # Custom partitioning
            log "Please partition the disk manually using fdisk or parted"
            # Custom partitioning logic would go here
            return 0
            ;;
    esac
    
    # Format the partitions
    format_partitions "$efi_partition" "$root_partition" "$filesystem" "$swap_partition" "$swap_size_mb"
    
    # Generate fstab file
    generate_fstab
    
    log "Partitioning completed"
    return 0
}

# Function to determine system RAM
get_system_ram() {
    # Get total memory in KB and convert to GB
    local mem_kb
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$(( mem_kb / 1024 / 1024 ))
    
    # Default to 8GB if we can't determine or in test mode
    if [[ $mem_gb -lt 1 || "$TEST_MODE" -eq 1 ]]; then
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
    if [[ "$TEST_MODE" -eq 1 ]]; then
        # In test mode, default to option 2
        choice=2
        log "Selecting default swap option 2 in test mode: $half_gb GB"
    else
        read -r -p "Select swap size option (1-4): " choice
    fi
    
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

# Function to gather disk information
get_disk_info() {
    local disk=$1
    
    # Get disk size in human-readable format
    local size
    size=$(lsblk -dn -o SIZE "$disk")
    
    # Get disk model
    local model
    model=$(lsblk -dn -o MODEL "$disk")
    
    echo "Disk: $disk"
    echo "Size: $size"
    echo "Model: $model"
    
    return 0
}
