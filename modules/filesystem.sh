#!/bin/bash
# filesystem.sh
get_partition_name() {
    local disk="$1"
    local part_num="$2"
    [[ "$disk" =~ nvme[0-9]+n[0-9]+$ ]] && echo "${disk}p${part_num}" || echo "${disk}${part_num}"
}

calculate_swap_size() {
    local ram_kB
    ram_kB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local swap_mib=$(( ram_kB / 2 / 1024 ))
    [[ $swap_mib -lt 1024 ]] && swap_mib=1024  # Minimum 1GB
    echo "$swap_mib"
}

perform_partitioning() {
    local disk="$1"
    local choice="$2"
    local swap_size
    swap_size=$(calculate_swap_size)
    local esp
    esp=$(get_partition_name "$disk" 1)
    local swp
    swp=$(get_partition_name "$disk" 2)
    local root
    root=$(get_partition_name "$disk" 3)

    case "$choice" in
        "auto_ext4")
            log "Partitioning with ext4..."
            parted -s "$disk" mkpart primary fat32 1MiB 513MiB "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
            parted -s "$disk" set 1 esp on "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
            parted -s "$disk" mkpart primary linux-swap 513MiB "$((513 + swap_size))MiB" "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
            parted -s "$disk" mkpart primary ext4 "$((513 + swap_size))MiB" 100% "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
            partprobe "$disk" "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
            wipefs -a "$esp" "$swp" "$root" "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
            log "Formatting partitions..."
            mkfs.fat -F32 -I "$esp" "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
            mkswap "$swp" "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")" && swapon "$swp" "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
            mkfs.ext4 -F "$root" "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
            log "Mounting filesystems..."
            mount "$root" /mnt "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
            mkdir -p /mnt/efi "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
            mount "$esp" /mnt/efi "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
            ;;
        "auto_btrfs")
            log "Partitioning with BTRFS..."
            # Similar to above, with BTRFS subvolume setup (omitted for brevity)
            ;;
        "manual")
            log "Launching cfdisk for manual partitioning..."
            cfdisk "$disk"
            log "Manual partitioning done."
            echo -e "${YELLOW}Next steps:${NC}" > /dev/tty
            echo "1. Create filesystems (e.g., mkfs.ext4 /dev/sdX1)" > /dev/tty
            echo "2. Mount root to /mnt (e.g., mount /dev/sdX2 /mnt)" > /dev/tty
            echo "3. Mount EFI to /mnt/efi if needed" > /dev/tty
            prompt "Ready to proceed? (y/n): " ready
            local ready
            read -r ready
            [[ "$ready" =~ ^[Yy] ]] || { log "${RED}Aborting due to incomplete setup.${NC}"; exit 1; }
            ;;
    esac
}
