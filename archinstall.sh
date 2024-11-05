#!/bin/bash

# Arch Linux Automated Installation Script with Enhanced Manual Partitioning

set -e

# Function to display an error message and exit
error_exit() {
    dialog --title "Error" --msgbox "$1" 8 50
    clear
    exit 1
}

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Check for dialog and install if missing
if ! command -v dialog &> /dev/null; then
    pacman -Sy dialog --noconfirm
fi

# Temporary file for dialog inputs
TEMP=$(mktemp)

# Function to list available disks
list_disks() {
    lsblk -d -o NAME,SIZE,MODEL,TYPE | grep "disk" | awk '{print $1 " (" $2 " - " $3 ")"}'
}

# Function to select a disk
select_disk() {
    DISKS=($(list_disks | awk '{print $1}'))
    if [ ${#DISKS[@]} -eq 0 ]; then
        error_exit "No disks found. Exiting."
    fi

    DISK_OPTIONS=()
    for DISK in "${DISKS[@]}"; do
        SIZE=$(lsblk -d -o SIZE -n /dev/"$DISK")
        MODEL=$(lsblk -d -o MODEL -n /dev/"$DISK" | awk '{for(i=2;i<=NF;i++) printf $i " "; print ""}')
        DISK_OPTIONS+=("$DISK" "$SIZE - $MODEL")
    done

    dialog --clear --title "Select Disk" \
    --menu "Choose the disk to install Arch Linux on:" 20 70 10 \
    "${DISK_OPTIONS[@]}" 2> "$TEMP"

    if [ $? -ne 0 ]; then
        error_exit "No disk selected. Exiting."
    fi

    SELECTED_DISK=$(cat "$TEMP")
    DISK="/dev/$SELECTED_DISK"
    clear
}

# Function for recommended partition scheme
recommended_partitioning() {
    # Create GPT label
    parted "$DISK" --script mklabel gpt

    # Create EFI partition (300MiB)
    parted "$DISK" --script mkpart primary fat32 1MiB 301MiB
    parted "$DISK" --script set 1 esp on

    # Create Swap partition (4GiB)
    parted "$DISK" --script mkpart primary linux-swap 301MiB 4301MiB

    # Create Root partition (remaining space)
    parted "$DISK" --script mkpart primary btrfs 4301MiB 100%

    # Assign partition variables
    EFI_PART="${DISK}1"
    SWAP_PART="${DISK}2"
    ROOT_PART="${DISK}3"

    # Format partitions
    mkfs.fat -F32 "$EFI_PART"
    mkswap "$SWAP_PART"
    swapon "$SWAP_PART"
    mkfs.btrfs -f "$ROOT_PART"

    # Mount Root partition and create subvolumes
    mount "$ROOT_PART" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@pkg
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/.snapshots

    # Unmount and remount with subvolumes
    umount /mnt
    mount -o compress=zstd,subvol=@ "$ROOT_PART" /mnt
    mkdir -p /mnt/{home,var/cache/pacman/pkg,var/log,.snapshots}
    mount -o compress=zstd,subvol=@home "$ROOT_PART" /mnt/home
    mount -o compress=zstd,subvol=@pkg "$ROOT_PART" /mnt/var/cache/pacman/pkg
    mount -o compress=zstd,subvol=@log "$ROOT_PART" /mnt/var/log
    mount -o compress=zstd,subvol=@snapshots "$ROOT_PART" /mnt/.snapshots

    clear
}

# Function for manual partitioning
manual_partitioning() {
    # Launch cfdisk for manual partitioning
    dialog --msgbox "Launching cfdisk for manual partitioning.\n\nPlease create the necessary partitions.\n\nPress OK to continue." 12 60
    clear
    cfdisk "$DISK"

    # After partitioning, list available partitions on the selected disk
    PARTITIONS=($(lsblk -rpno NAME,TYPE | grep part | grep "^${DISK}" | awk '{print $1}'))

    if [ ${#PARTITIONS[@]} -eq 0 ]; then
        error_exit "No partitions found on $DISK. Exiting."
    fi

    # Initialize associative arrays to store mount points and filesystems
    declare -A MOUNT_POINTS
    declare -A FILESYSTEMS

    # Define common mount points
    COMMON_MOUNT_POINTS=("/", "/home", "/var", "/boot", "/boot/efi", "swap")

    # Iterate through each partition and collect mount point and filesystem
    for PART in "${PARTITIONS[@]}"; do
        # Get partition size
        SIZE=$(lsblk -o SIZE -n "$PART")

        # Prompt for mount point using a menu
        dialog --clear --title "Mount Point Selection" \
        --menu "Select the mount point for partition $PART ($SIZE):" 15 60 7 \
        1 "/" \
        2 "/home" \
        3 "/var" \
        4 "/boot" \
        5 "/boot/efi" \
        6 "swap" \
        7 "Custom" 2> "$TEMP"

        MP_CHOICE=$(<"$TEMP")

        case $MP_CHOICE in
            1)
                MOUNT_POINT="/"
                ;;
            2)
                MOUNT_POINT="/home"
                ;;
            3)
                MOUNT_POINT="/var"
                ;;
            4)
                MOUNT_POINT="/boot"
                ;;
            5)
                MOUNT_POINT="/boot/efi"
                ;;
            6)
                MOUNT_POINT="swap"
                ;;
            7)
                dialog --inputbox "Enter the mount point for partition $PART:" 8 60 2> "$TEMP"
                MOUNT_POINT=$(<"$TEMP")
                ;;
            *)
                error_exit "Invalid mount point selection. Exiting."
                ;;
        esac

        # Prevent duplicate mount points
        if [[ " ${MOUNT_POINTS[@]} " =~ " ${MOUNT_POINT} " ]]; then
            error_exit "Mount point $MOUNT_POINT is already assigned to another partition. Exiting."
        fi

        MOUNT_POINTS["$PART"]="$MOUNT_POINT"

        # Prompt for filesystem type using a menu
        dialog --clear --title "Filesystem Selection" \
        --menu "Choose the filesystem for partition $PART ($MOUNT_POINT):" 15 60 5 \
        1 "btrfs" \
        2 "ext4" \
        3 "xfs" \
        4 "swap" \
        5 "Other" 2> "$TEMP"

        FS_CHOICE=$(<"$TEMP")

        case $FS_CHOICE in
            1)
                FILESYSTEM="btrfs"
                ;;
            2)
                FILESYSTEM="ext4"
                ;;
            3)
                FILESYSTEM="xfs"
                ;;
            4)
                FILESYSTEM="swap"
                ;;
            5)
                dialog --inputbox "Enter the filesystem type for partition $PART:" 8 60 2> "$TEMP"
                FILESYSTEM=$(<"$TEMP")
                ;;
            *)
                error_exit "Invalid filesystem selection. Exiting."
                ;;
        esac

        FILESYSTEMS["$PART"]="$FILESYSTEM"
    done

    # Display summary and confirm
    SUMMARY=""
    for PART in "${PARTITIONS[@]}"; do
        SUMMARY+="Partition: $PART\nMount Point: ${MOUNT_POINTS[$PART]}\nFilesystem: ${FILESYSTEMS[$PART]}\n\n"
    done

    dialog --clear --title "Partition Summary" --msgbox "$SUMMARY" 20 60

    # Confirm partition setup
    dialog --yesno "Proceed with formatting and mounting the partitions as per the summary?" 10 60
    if [ $? -ne 0 ]; then
        error_exit "Installation aborted by user."
    fi

    # Format and mount partitions
    for PART in "${PARTITIONS[@]}"; do
        FS=${FILESYSTEMS[$PART]}
        MP=${MOUNT_POINTS[$PART]}

        if [[ "$FS" == "swap" ]]; then
            # Initialize swap
            mkswap "$PART"
            swapon "$PART"
        else
            # Format partition
            if [[ "$FS" == "btrfs" ]]; then
                mkfs.btrfs -f "$PART"
            else
                mkfs."$FS" -F "$PART"
            fi

            # Mount partition
            if [[ "$MP" == "/" ]]; then
                mount "$PART" /mnt
            else
                mkdir -p /mnt"$MP"
                mount "$PART" /mnt"$MP"
            fi
        fi
    done

    # Check if swap is set; if not, prompt for memory compression options
    SWAP_EXISTS=0
    for PART in "${PARTITIONS[@]}"; do
        if [[ "${FILESYSTEMS[$PART]}" == "swap" ]]; then
            SWAP_EXISTS=1
            break
        fi
    done

    if [ "$SWAP_EXISTS" -eq 0 ]; then
        # No swap partition; offer memory compression options
        dialog --clear --title "Memory Compression" \
        --menu "Choose a memory compression method to enable (optional):" 15 50 4 \
        1 "zram" \
        2 "zcache" \
        3 "zswap" \
        4 "None" 2> "$TEMP"

        MEM_COMP=$(<"$TEMP")
    else
        MEM_COMP="4"  # No memory compression if swap exists
    fi

    clear
}

# Function to handle bootloader installation
install_bootloader() {
    arch-chroot /mnt /bin/bash <<EOF
# Install necessary packages
pacman -S --noconfirm grub efibootmgr networkmanager

# Enable NetworkManager
systemctl enable NetworkManager

# Detect EFI system
if [ -d /sys/firmware/efi ]; then
    mkdir -p /boot/efi
    mount $EFI_PART /boot/efi
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    # BIOS system
    grub-install --target=i386-pc $DISK
fi

# Generate GRUB configuration
grub-mkconfig -o /boot/grub/grub.cfg
EOF
}

# Function to configure system settings in chroot
configure_system() {
    arch-chroot /mnt /bin/bash <<EOF
# Setup Locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Setup Timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Setup Networking
echo "$HOSTNAME" > /etc/hostname

# Configure /etc/hosts
echo "127.0.0.1   localhost" > /etc/hosts
echo "::1         localhost" >> /etc/hosts
echo "127.0.1.1   $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Enable NetworkManager
systemctl enable NetworkManager
EOF
}

# Function to configure memory compression
configure_memory_compression() {
    if [ "$MEM_COMP" == "1" ]; then
        # Install and configure zram
        arch-chroot /mnt pacman -S --noconfirm zram-generator
        cat <<EOL > /mnt/etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = lz4
EOL
    elif [ "$MEM_COMP" == "2" ]; then
        # Install and configure zcache
        arch-chroot /mnt pacman -S --noconfirm zcache
        # Example configuration; adjust as needed
        cat <<EOL > /mnt/etc/zcache.conf
zcache zcache /var/cache/zcache
EOL
        arch-chroot /mnt systemctl enable zcache
    elif [ "$MEM_COMP" == "3" ]; then
        # Install and configure zswap
        arch-chroot /mnt pacman -S --noconfirm zswap
        # Modify GRUB config to include zswap parameters
        arch-chroot /mnt sed -i 's/^GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="zswap.enabled=1 zswap.compressor=lz4 /' /etc/default/grub
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    fi
}

# Main Installation Flow

# Step 1: Choose Partition Scheme
dialog --clear --title "Partition Scheme Selection" \
--menu "Choose a partition scheme:" 15 60 2 \
1 "Use Recommended Btrfs Partition Scheme" \
2 "Manual Partitioning" 2> "$TEMP"

PARTITION_CHOICE=$(cat "$TEMP")

case $PARTITION_CHOICE in
    1)
        # Recommended Partition Scheme
        select_disk
        recommended_partitioning
        ;;
    2)
        # Manual Partitioning
        select_disk
        manual_partitioning
        ;;
    *)
        error_exit "Invalid selection. Exiting."
        ;;
esac

# Step 2: Install Base System
dialog --msgbox "Installing the base system. This may take a few minutes..." 7 50
pacstrap /mnt base base-devel linux linux-firmware vim dialog

# Step 3: Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Step 4: Chroot and Configure System
# Prompt for hostname
dialog --inputbox "Enter your hostname:" 8 40 2> "$TEMP"
HOSTNAME=$(cat "$TEMP")

if [[ -z "$HOSTNAME" ]]; then
    HOSTNAME="archlinux"
fi

configure_system

# Step 5: Install Bootloader
install_bootloader

# Step 6: Configure Memory Compression (if applicable)
if [ "$MEM_COMP" != "4" ]; then
    configure_memory_compression
fi

# Step 7: Final Configurations
arch-chroot /mnt hwclock --systohc

# Timezone setup (prompt user)
dialog --inputbox "Enter your timezone (e.g., Europe/London):" 8 60 2> "$TEMP"
TIMEZONE=$(cat "$TEMP")

if [[ -z "$TIMEZONE" ]]; then
    TIMEZONE="UTC"
fi

arch-chroot /mnt ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
arch-chroot /mnt hwclock --systohc

# Finalizing Installation
dialog --msgbox "Installation complete. Unmounting partitions and rebooting." 7 50

# Unmount all mounted partitions and disable swap
umount -R /mnt
swapoff -a

# Remove temporary file
rm -f "$TEMP"

# Reboot the system
reboot
