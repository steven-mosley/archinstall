#!/bin/bash

# Requires root privileges to execute
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root!"
  exit 1
fi

set -e

# Ensure script runs interactively (TTY fix for piping)
if [[ ! -t 0 ]]; then
  exec 3<>/dev/tty && cat <&3 | bash || exit
fi

# Variables
SWAP_SIZE=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 2048 )) # Swap size = half of RAM in MiB

# Function to detect disk type (SATA or NVMe)
get_partition_suffix() {
  if [[ "$1" == *"nvme"* ]]; then
    echo "p" # NVMe uses "p" before partition numbers
  else
    echo ""  # SATA/SD/MMC disks use no extra suffix
  fi
}

# Prompt user to select a disk
select_disk() {
  echo "Available Disks:"
  lsblk -d -p -n -o NAME,SIZE | nl
  read -p "Enter the number corresponding to your disk: " disk_number
  selected_disk=$(lsblk -d -p -n -o NAME | sed -n "${disk_number}p")

  if [[ -z "$selected_disk" ]]; then
    echo "Invalid selection. Exiting."
    exit 1
  fi

  echo "Selected disk: $selected_disk"
}

# Wipe disk and create GPT partitions
partition_disk() {
  local disk="$1"
  local suffix
  suffix=$(get_partition_suffix "$disk")

  echo "Wiping existing partitions on $disk..."
  wipefs -a "$disk"
  parted -s "$disk" mklabel gpt

  echo "Creating partitions on $disk..."
  parted -s "$disk" mkpart primary fat32 1MiB 513MiB
  parted -s "$disk" set 1 esp on
  parted -s "$disk" mkpart primary linux-swap 513MiB "$((SWAP_SIZE + 513))MiB"
  parted -s "$disk" mkpart primary ext4 "$((SWAP_SIZE + 513))MiB" 100%

  echo "Formatting partitions..."
  mkfs.fat -F32 "${disk}${suffix}1"
  mkswap "${disk}${suffix}2" && swapon "${disk}${suffix}2"
  mkfs.ext4 "${disk}${suffix}3"

  echo "Mounting partitions..."
  mount "${disk}${suffix}3" /mnt
  mkdir -p /mnt/efi
  mount "${disk}${suffix}1" /mnt/efi
}

# Install the base system
install_base_system() {
  echo "Installing base system..."
  pacstrap /mnt base linux linux-firmware systemd-resolved
  genfstab -U /mnt >> /mnt/etc/fstab
}

# Configure the system
configure_system() {
  echo "Configuring system..."

  # Predefined list of locales
  locales=("en_US.UTF-8 UTF-8" "en_GB.UTF-8 UTF-8" "fr_FR.UTF-8 UTF-8" "de_DE.UTF-8 UTF-8")
  echo "Available Locales:"
  for i in "${!locales[@]}"; do
    echo "$((i + 1)). ${locales[$i]}"
  done
  while :; do
    read -p "Select your locale (1-${#locales[@]}): " locale_choice
    if [[ "$locale_choice" =~ ^[1-${#locales[@]}]$ ]]; then
      selected_locale="${locales[$((locale_choice - 1))]}"
      break
    else
      echo "Invalid choice. Try again."
    fi
  done
  echo "$selected_locale" >> /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
  echo "LANG=${selected_locale%% *}" > /mnt/etc/locale.conf

  # Hostname configuration
  read -p "Enter your hostname: " hostname
  echo "$hostname" > /mnt/etc/hostname
  echo "127.0.0.1 localhost" > /mnt/etc/hosts
  echo "::1 localhost" >> /mnt/etc/hosts
  echo "127.0.1.1 $hostname.localdomain $hostname" >> /mnt/etc/hosts

  # Timezone configuration
  timezone=$(curl -s https://ipapi.co/timezone)
  arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
  arch-chroot /mnt hwclock --systohc

  # Root password setup
  echo "Set the root password:"
  arch-chroot /mnt passwd

  # Minimal network setup with systemd-resolved
  echo "Enabling systemd-resolved for DNS resolution..."
  arch-chroot /mnt systemctl enable systemd-resolved
}

# Main execution flow
main() {
  select_disk
  partition_disk "$selected_disk"
  install_base_system
  configure_system
  echo "Installation complete! You can now reboot."
}

# Run the script
main
