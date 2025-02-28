#!/bin/bash
# Disk handling functions

# Function to display disk selection menu
create_disk_menu() {
    log "Scanning available disks..."
    local disks
    disks=$(lsblk -d -p -n -l -o NAME,SIZE,MODEL | grep -v "loop" | sort)
    
    if [[ -z "$disks" ]]; then
        log "No disks found. Cannot continue."
        exit 1
    fi
    
    log "Available disks:"
    local count=1
    local disk_options=()
    
    while IFS= read -r line; do
        disk_options+=("$line")
        echo "  $count. $line"
        ((count++))
    done <<< "$disks"
    
    prompt "Select disk (number): " disk_num
    
    if ! [[ "$disk_num" =~ ^[0-9]+$ ]] || [ "$disk_num" -lt 1 ] || [ "$disk_num" -gt "${#disk_options[@]}" ]; then
        log "Invalid selection."
        create_disk_menu
        return
    fi
    
    selected_disk=$(echo "${disk_options[$((disk_num-1))]}" | awk '{print $1}')
    log "Selected disk: $selected_disk"
}

# Function to verify disk has enough space
verify_disk_space() {
    local disk="$1"
    local min_size=10 # GB
    
    local size_gb
    size_gb=$(lsblk -b -d -n -o SIZE "$disk" | awk '{printf "%.0f", $1/1024/1024/1024}')
    
    if (( size_gb < min_size )); then
        log "Warning: Disk $disk has less than ${min_size}GB of space."
        prompt "Continue anyway? (y/n): " continue
        [[ "$continue" =~ ^[Yy] ]] || return 1
    fi
    
    return 0
}

# Function to wipe partitions
wipe_partitions() {
    log "Preparing to wipe partitions on $selected_disk"
    prompt "WARNING: This will DESTROY ALL DATA on $selected_disk. Continue? (y/n): " confirm
    
    if [[ "$confirm" =~ ^[Yy] ]]; then
        log "Wiping partitions..."
        # Clear partition table
        sgdisk --zap-all "$selected_disk" || { log "Failed to wipe partition table"; exit 1; }
        log "Partitions wiped successfully."
    else
        log "Operation cancelled."
        exit 0
    fi
}

# Function to show partition scheme menu
create_partition_menu() {
    log "Select partitioning scheme:"
    echo "  1. UEFI with separate /home"
    echo "  2. UEFI with single root partition"
    echo "  3. UEFI with separate /home and /var"
    
    prompt "Enter your choice (number): " choice
    
    if ! [[ "$choice" =~ ^[1-3]$ ]]; then
        log "Invalid selection."
        create_partition_menu
        return
    fi
    
    partition_choice="$choice"
    log "Selected partitioning scheme: $partition_choice"
}

# Function to perform actual partitioning
perform_partitioning() {
    local disk="$1"
    local scheme="$2"
    
    log "Partitioning $disk with scheme $scheme..."
    
    # Create GPT partition table
    sgdisk --clear "$disk" || { log "Failed to create GPT table"; exit 1; }
    
    # Create EFI partition (512MB)
    sgdisk --new=1:0:+512M --typecode=1:ef00 --change-name=1:"EFI System" "$disk" || exit 1
    
    case "$scheme" in
        1)  # UEFI with separate /home
            # Create root partition (30GB)
            sgdisk --new=2:0:+30G --typecode=2:8300 --change-name=2:"Linux root" "$disk" || exit 1
            # Create home partition (remaining space)
            sgdisk --new=3:0:0 --typecode=3:8300 --change-name=3:"Linux home" "$disk" || exit 1
            ;;
        2)  # UEFI with single root partition
            # Create root partition (remaining space)
            sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:"Linux root" "$disk" || exit 1
            ;;
        3)  # UEFI with separate /home and /var
            # Create root partition (30GB)
            sgdisk --new=2:0:+30G --typecode=2:8300 --change-name=2:"Linux root" "$disk" || exit 1
            # Create var partition (10GB)
            sgdisk --new=3:0:+10G --typecode=3:8300 --change-name=3:"Linux var" "$disk" || exit 1
            # Create home partition (remaining space)
            sgdisk --new=4:0:0 --typecode=4:8300 --change-name=4:"Linux home" "$disk" || exit 1
            ;;
    esac
    
    log "Partitioning complete."
}

# Function to format partitions
format_partitions() {
    log "Formatting partitions..."
    # Logic to format partitions
    return 0
}

# Function to mount partitions
mount_partitions() {
    log "Mounting partitions..."
    # Logic to mount partitions
    return 0
}

# Function to detect existing partitions
detect_partitions() {
    log "Detecting existing partitions..."
    # Logic to detect partitions
    return 0
}

# Function to create swap
create_swap() {
    log "Creating swap space..."
    # Logic to create and enable swap
    return 0
}
