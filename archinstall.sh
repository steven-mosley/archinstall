#!/bin/bash

# Bash script to automate Linux installation and configuration.
# Requires root privileges.

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

# Function to create disk menu and select a disk
create_disk_menu() {
  echo "Available Disks:"

  # Filter out unwanted devices like loop and DVD drives
  lsblk -d -p -n -o NAME,SIZE,MODEL | grep -Ev "loop|sr" | nl

  # Prompt user for selection
  while :; do
    read -r -p "Enter the number corresponding to your disk: " disk_number </dev/tty
    selected_disk=$(lsblk -d -p -n -o NAME | grep -Ev "loop|sr" | sed -n "${disk_number}p")

    if [[ -z "$selected_disk" ]]; then
      echo "Invalid selection. Try again."
    else
      echo "Selected disk: $selected_disk"
      break
    fi
  done
}

# Function to determine partition naming scheme (sda vs nvme)
get_partition_name() {
  local disk=$1
  if [[ "$disk" =~ nvme ]]; then
    echo "${disk}p"
  else
    echo "${disk}"
  fi
}

# Function to create partition menu
create_partition_menu() {
  echo "Partitioning Methods:"
  echo "1. Automatic partitioning with ext4"
  echo "2. Automatic partitioning with BTRFS"
  echo "3. Manual partitioning (using cfdisk)"

  while :; do
    read -r -p "Enter your choice (1-3): " partition_method </dev/tty
    case $partition_method in
      1) partition_choice="noob_ext4"; break ;;
      2) partition_choice="noob_btrfs"; break ;;
      3) partition_choice="manual"; break ;;
      *)
        echo "Invalid choice. Try again."
        ;;
    esac
  done
}

# Function to perform partitioning
perform_partitioning() {
  local disk=$1
  local choice=$2
  local part_prefix=$(get_partition_name "$disk")

  # Ensure disk is ready
  umount -R "$disk"* 2>/dev/null || true
  swapoff "$disk"* 2>/dev/null || true

  case $choice in
  "noob_ext4")
    echo "Performing automatic partitioning with ext4..."
    parted -s "$disk" mklabel gpt
    parted -s "$disk" mkpart primary fat32 1MiB 513MiB
    parted -s "$disk" set 1 esp on
    parted -s "$disk" mkpart primary linux-swap 513MiB 4.5GiB
    parted -s "$disk" mkpart primary ext4 4.5GiB 100%

    mkfs.fat -F32 "${part_prefix}1"
    mkswap "${part_prefix}2" && swapon "${part_prefix}2"
    mkfs.ext4 "${part_prefix}3"

    mount "${part_prefix}3" /mnt
    mkdir -p /mnt/efi
    mount "${part_prefix}1" /mnt/efi
    ;;

  "noob_btrfs")
    echo "Performing automatic partitioning with BTRFS..."
    parted -s "$disk" mklabel gpt
    parted -s "$disk" mkpart primary fat32 1MiB 513MiB
    parted -s "$disk" set 1 esp on
    parted -s "$disk" mkpart primary linux-swap 513MiB 4.5GiB
    parted -s "$disk" mkpart primary btrfs 4.5GiB 100%

    mkfs.fat -F32 "${part_prefix}1"
    mkswap "${part_prefix}2" && swapon "${part_prefix}2"
    mkfs.btrfs "${part_prefix}3"

    mount "${part_prefix}3" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@pkg
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/@snapshots
    umount /mnt

    mount -o subvol=@,compress=zstd,noatime "${part_prefix}3" /mnt
    mkdir -p /mnt/{efi,home,var/cache/pacman/pkg,var/log,.snapshots}
    mount -o subvol=@home,compress=zstd,noatime "${part_prefix}3" /mnt/home
    mount -o subvol=@pkg,compress=zstd,noatime "${part_prefix}3" /mnt/var/cache/pacman/pkg
    mount -o subvol=@log,compress=zstd,noatime "${part_prefix}3" /mnt/var/log
    mount -o subvol=@snapshots,compress=zstd,noatime "${part_prefix}3" /mnt/.snapshots
    mount "${part_prefix}1" /mnt/efi
    ;;

  "manual")
    echo "Launching cfdisk for manual partitioning..."
    cfdisk "$disk"
    ;;
  esac
}

# Function to install base system
install_base_system() {
  echo "Installing base system..."
  pacstrap /mnt base linux linux-firmware
  genfstab -U /mnt >>/mnt/etc/fstab
}

# Function to configure system
configure_system() {
  echo "Configuring system..."

  # Predefined list of locales
  locales=("en_US.UTF-8 UTF-8" "en_GB.UTF-8 UTF-8" "fr_FR.UTF-8 UTF-8" "de_DE.UTF-8 UTF-8")
  echo "Available Locales:"
  for i in "${!locales[@]}"; do
    echo "$((i + 1)). ${locales[$i]}"
  done
  while :; do
    read -r -p "Select your locale (1-${#locales[@]}): " locale_choice </dev/tty
    if [[ "$locale_choice" =~ ^[1-${#locales[@]}]$ ]]; then
      locale="${locales[$((locale_choice - 1))]}"
      break
    else
      echo "Invalid choice. Try again."
    fi
  done

  echo "$locale" > /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
  echo "LANG=${locale%% *}" > /mnt/etc/locale.conf

  # Hostname configuration
  read -r -p "Enter your hostname: " hostname </dev/tty
  echo "$hostname" > /mnt/etc/hostname
  echo "127.0.0.1 localhost" > /mnt/etc/hosts
  echo "::1 localhost" >> /mnt/etc/hosts
  echo "127.0.1.1 $hostname.localdomain $hostname" >> /mnt/etc/hosts

  # Timezone configuration
  arch-chroot /mnt ln -sf /usr/share/zoneinfo/$(curl -s https://ipapi.co/timezone) /etc/localtime
  arch-chroot /mnt hwclock --systohc

  # Root password setup
  echo "Set the root password:"
  arch-chroot /mnt passwd

  # Bootloader installation
  echo "Installing GRUB bootloader..."
  arch-chroot /mnt pacman -S --noconfirm grub efibootmgr
  arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

# Main function
main() {
  create_disk_menu
  create_partition_menu
  perform_partitioning "$selected_disk" "$partition_choice"
  install_base_system
  configure_system
  echo "Installation complete! You can now reboot."
}

main
