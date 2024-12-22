#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Install necessary packages
pacman -Sy --noconfirm dialog

# Function to display a menu using dialog
show_menu() {
  dialog --clear --backtitle "Arch Linux Installation" \
    --title "Main Menu" \
    --menu "Choose one of the following options:" 15 50 4 \
    1 "Partition Disk" \
    2 "Format Partitions" \
    3 "Mount Partitions" \
    4 "Install Base System" \
    5 "Configure System" \
    6 "Exit" 2>menu_choice.txt

  menuitem=$(<menu_choice.txt)
  case $menuitem in
  1) partition_disk ;;
  2) format_partitions ;;
  3) mount_partitions ;;
  4) install_base_system ;;
  5) configure_system ;;
  6) exit 0 ;;
  esac
}

partition_disk() {
  dialog --clear --backtitle "Partition Disk" \
    --title "Partition Disk" \
    --msgbox "You will now be dropped into cfdisk to partition your disk." 10 50
  cfdisk
  show_menu
}

format_partitions() {
  dialog --clear --backtitle "Format Partitions" \
    --title "Format Partitions" \
    --msgbox "Formatting partitions..." 10 50
  mkfs.ext4 /dev/sda1
  mkfs.ext4 /dev/sda2
  mkswap /dev/sda3
  swapon /dev/sda3
  show_menu
}

mount_partitions() {
  dialog --clear --backtitle "Mount Partitions" \
    --title "Mount Partitions" \
    --msgbox "Mounting partitions..." 10 50
  mount /dev/sda1 /mnt
  mkdir /mnt/home
  mount /dev/sda2 /mnt/home
  show_menu
}

install_base_system() {
  dialog --clear --backtitle "Install Base System" \
    --title "Install Base System" \
    --msgbox "Installing base system..." 10 50
  pacstrap /mnt base linux linux-firmware
  genfstab -U /mnt >>/mnt/etc/fstab
  show_menu
}

configure_system() {
  dialog --clear --backtitle "Configure System" \
    --title "Configure System" \
    --msgbox "Configuring system..." 10 50
  arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "archlinux" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 archlinux.localdomain archlinux" >> /etc/hosts
mkinitcpio -P
passwd
EOF
  show_menu
}

# Start the menu
show_menu
