#!/bin/bash

# Arch Linux installation script with NVMe and piping compatibility.
# Requires root privileges.

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

# Function to safely prompt for user input
prompt() {
  echo "$1" > /dev/tty
  read -r "$2" < /dev/tty
}

# Function to create disk menu and select a disk
create_disk_menu() {
  echo "Available Disks:" > /dev/tty
  lsblk -d -p -n -o NAME,SIZE,MODEL | nl > /dev/tty
  prompt "Enter the number corresponding to your disk: " disk_number
  selected_disk=$(lsblk -d -p -n -o NAME | sed -n "${disk_number}p")
  if [[ -z "$selected_disk" ]]; then
    echo "Invalid selection. Try again." > /dev/tty
    create_disk_menu
  else
    echo "Selected disk: $selected_disk" > /dev/tty
  fi
}

# Function to determine partition naming
get_partition_name() {
  local disk=$1
  local part_number=$2
  if [[ "$disk" =~ nvme[0-9]n[0-9]$ ]]; then
    echo "${disk}p${part_number}"
  else
    echo "${disk}${part_number}"
  fi
}

# Function to wipe existing partitions
wipe_partitions() {
  echo "Wiping existing partitions on $selected_disk..." > /dev/tty
  wipefs -a "$selected_disk"
  parted -s "$selected_disk" mklabel gpt
  echo "Existing partitions wiped, and GPT table created." > /dev/tty
}

# Function to calculate swap size
calculate_swap_size() {
  local ram_size=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local swap_size=$((ram_size / 2 / 1024)) # Calculate swap as half the RAM in MiB
  echo "$swap_size"
}

# Function to perform partitioning
perform_partitioning() {
  local disk=$1
  local choice=$2
  local swap_size=$(calculate_swap_size)

  # Ensure disk is unmounted
  umount -R "$disk"* 2>/dev/null || true
  swapoff "$disk"* 2>/dev/null || true

  case $choice in
  "noob_ext4")
    echo "Performing automatic partitioning with ext4..." > /dev/tty
    local esp=$(get_partition_name "$disk" 1)
    local swap=$(get_partition_name "$disk" 2)
    local root=$(get_partition_name "$disk" 3)

    parted -s "$disk" mkpart primary fat32 1MiB 513MiB
    parted -s "$disk" set 1 esp on
    parted -s "$disk" mkpart primary linux-swap 513MiB "$((513 + swap_size))MiB"
    parted -s "$disk" mkpart primary ext4 "$((513 + swap_size))MiB" 100%
    mkfs.fat -F32 "$esp"
    mkswap "$swap" && swapon "$swap"
    mkfs.ext4 "$root"
    mount "$root" /mnt
    mkdir -p /mnt/efi
    mount "$esp" /mnt/efi
    ;;
  "noob_btrfs")
    echo "Performing automatic partitioning with BTRFS..." > /dev/tty
    local esp=$(get_partition_name "$disk" 1)
    local swap=$(get_partition_name "$disk" 2)
    local root=$(get_partition_name "$disk" 3)

    parted -s "$disk" mkpart primary fat32 1MiB 513MiB
    parted -s "$disk" set 1 esp on
    parted -s "$disk" mkpart primary linux-swap 513MiB "$((513 + swap_size))MiB"
    parted -s "$disk" mkpart primary btrfs "$((513 + swap_size))MiB" 100%
    mkfs.fat -F32 "$esp"
    mkswap "$swap" && swapon "$swap"
    mkfs.btrfs "$root"
    mount "$root" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@pkg
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/@snapshots
    umount /mnt

    mount -o subvol=@,compress=zstd,noatime "$root" /mnt
    mkdir -p /mnt/{efi,home,var/cache/pacman/pkg,var/log,.snapshots}
    mount -o subvol=@home,compress=zstd,noatime "$root" /mnt/home
    mount -o subvol=@pkg,compress=zstd,noatime "$root" /mnt/var/cache/pacman/pkg
    mount -o subvol=@log,compress=zstd,noatime "$root" /mnt/var/log
    mount -o subvol=@snapshots,compress=zstd,noatime "$root" /mnt/.snapshots
    mount "$esp" /mnt/efi
    ;;
  "manual")
    echo "Launching cfdisk for manual partitioning..." > /dev/tty
    cfdisk "$disk"
    ;;
  esac
}

# Function to install base system
install_base_system() {
  echo "Installing base system..." > /dev/tty
  pacstrap /mnt base linux linux-firmware
  genfstab -U /mnt >>/mnt/etc/fstab
}

# Function to configure system
configure_system() {
  echo "Configuring system..." > /dev/tty

  # Predefined list of locales
  locales=("en_US.UTF-8 UTF-8" "en_GB.UTF-8 UTF-8" "fr_FR.UTF-8 UTF-8" "de_DE.UTF-8 UTF-8")
  echo "Available Locales:" > /dev/tty
  for i in "${!locales[@]}"; do
    echo "$((i + 1)). ${locales[$i]}" > /dev/tty
  done
  while :; do
    prompt "Select your locale (1-${#locales[@]}): " locale_choice
    if [[ "$locale_choice" =~ ^[1-${#locales[@]}]$ ]]; then
      locale="${locales[$((locale_choice - 1))]}"
      break
    else
      echo "Invalid choice. Try again." > /dev/tty
    fi
  done

  echo "$locale" > /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
  echo "LANG=$(echo "$locale" | awk '{print $1}')" > /mnt/etc/locale.conf

  # Hostname configuration
  prompt "Enter your hostname: " hostname
  echo "$hostname" > /mnt/etc/hostname
  echo "127.0.0.1 localhost" > /mnt/etc/hosts
  echo "::1 localhost" >> /mnt/etc/hosts
  echo "127.0.1.1 $hostname.localdomain $hostname" >> /mnt/etc/hosts

  # Timezone configuration
  arch-chroot /mnt ln -sf /usr/share/zoneinfo/$(curl -s https://ipapi.co/timezone) /etc/localtime
  arch-chroot /mnt hwclock --systohc

  # Root password setup
  echo "Set the root password:" > /dev/tty
  arch-chroot /mnt passwd

  # Bootloader installation
  echo "Installing GRUB bootloader..." > /dev/tty
  arch-chroot /mnt pacman -S --noconfirm grub efibootmgr
  arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

# Function to set up minimal network configuration
setup_network() {
  echo "Setting up minimal network configuration..." > /dev/tty
  arch-chroot /mnt pacman -S --noconfirm dhcpcd
  arch-chroot /mnt systemctl enable dhcpcd.service
}

# Main function
main() {
  create_disk_menu
  wipe_partitions
  create_partition_menu
  perform_partitioning "$selected_disk" "$partition_choice"
  install_base_system
  setup_network
  configure_system
  echo "Installation complete! You can now reboot." > /dev/tty
}

main
