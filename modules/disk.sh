# disk.sh
create_disk_menu() {
    echo -e "${YELLOW}Select a disk:${NC}" > /dev/tty
    lsblk -d -p -n -o NAME,SIZE,TYPE | grep -E "disk" | grep -v loop | nl -w2 -s') ' > /dev/tty
    prompt "Enter disk number: " disk_number
    selected_disk=$(lsblk -d -p -n -o NAME,TYPE | grep disk | grep -v loop | awk '{print $1}' | sed -n "${disk_number}p")
    [[ -z "$selected_disk" ]] && { echo -e "${RED}Invalid selection.${NC}" > /dev/tty; create_disk_menu; }
    echo -e "${RED}WARNING: All data on $selected_disk will be wiped!${NC}" > /dev/tty
    prompt "Confirm (y/n): " confirm
    [[ "$confirm" =~ ^[Yy] ]] || create_disk_menu
    echo -e "${GREEN}Selected: $selected_disk${NC}" > /dev/tty
}

verify_disk_space() {
    local disk="$1"
    local min_size=$((20 * 1024 * 1024 * 1024))
    local disk_size=$(blockdev --getsize64 "$disk")
    ((disk_size < min_size)) && { log "${RED}Disk too small (<20GB)!${NC}"; return 1; }
}

wipe_partitions() {
    log "Checking for mounted partitions..."
    if mount | grep -q "$selected_disk"; then
        log "${RED}Unmounting partitions on $selected_disk...${NC}"
        umount -R "$selected_disk"* 2>/dev/null || { log "${RED}Failed to unmount!${NC}"; exit 1; }
    fi
    log "Wiping disk..."
    for part in $(lsblk -n -o NAME "$selected_disk"); do
        [[ -b "/dev/$part" ]] && swapoff "/dev/$part" 2>/dev/null || true
    done
    wipefs -a "$selected_disk" $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
    parted -s "$selected_disk" mklabel gpt $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
}

create_partition_menu() {
    echo -e "${YELLOW}Partitioning options:${NC}" > /dev/tty
    echo "1) Auto (ext4)" > /dev/tty
    echo "2) Auto (BTRFS)" > /dev/tty
    echo "3) Manual (cfdisk)" > /dev/tty
    prompt "Choose (1-3): " choice
    case "$choice" in
        1) partition_choice="auto_ext4" ;;
        2) partition_choice="auto_btrfs" ;;
        3) partition_choice="manual" ;;
        *) echo -e "${RED}Invalid choice.${NC}" > /dev/tty; create_partition_menu ;;
    esac
    echo -e "${GREEN}Selected: $partition_choice${NC}" > /dev/tty
}
