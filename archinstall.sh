#!/bin/bash

# Arch Installer v2.0 - Burn it down and rebuild
# Let's make Arch sexy. Minimal and Custom installs. Flexibility, usability, and no stupid errors. Just don't fuck it up.

set -e

# Prerequisite packages
packages=(
  dialog
  gptfdisk
  util-linux
  arch-install-scripts
  btrfs-progs
  refind
  zram-generator
  networkmanager
  sudo
  zsh
)

# Function to install packages if missing
install_packages() {
  for pkg in "${packages[@]}"; do
    if ! pacman -Qi "$pkg" &> /dev/null; then
      echo "Installing $pkg..."
      pacman -Sy --noconfirm "$pkg"
    fi
  done
}

# Check if the script is run as root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    dialog --msgbox "Please run this script as root." 5 40
    exit 1
  fi
}

# Check UEFI Boot
check_uefi() {
  if [ ! -d /sys/firmware/efi/efivars ]; then
    dialog --msgbox "Your system is not in UEFI mode. Reboot in UEFI mode to proceed." 7 50
    exit 1
  fi
}

# Check Internet Connection
check_internet() {
  if ! ping -c 1 archlinux.org &> /dev/null; then
    dialog --msgbox "No internet connection detected. Please connect to the internet." 7 50
    exit 1
  fi
}

# Set Timezone and Locale
set_timezone() {
  available_regions=$(ls /usr/share/zoneinfo | grep -v 'posix\|right\|Etc\|SystemV\|Factory')
  region=$(dialog --stdout --title "Select Region" --menu "Select your region:" 20 60 15 $(echo "$available_regions" | awk '{print $1, $1}'))
  
  if [ -z "$region" ]; then
    dialog --msgbox "No region selected. Defaulting to UTC." 6 50
    region="UTC"
  fi
  
  available_cities=$(ls /usr/share/zoneinfo/"$region")
  city=$(dialog --stdout --title "Select City" --menu "Select your city:" 20 60 15 $(echo "$available_cities" | awk '{print $1, $1}'))
  if [ -z "$city" ]; then
    dialog --msgbox "No city selected. Defaulting to UTC." 6 50
    city="UTC"
  fi
  timezone="$region/$city"
  timedatectl set-timezone "$timezone"
}

# Choose Installation Type (Minimal or Custom)
choose_install_type() {
  install_type=$(dialog --stdout --title "Select Installation Type" --menu "Choose your installation type:" 15 70 2 \
    "Minimal" "Quick install with defaults" \
    "Custom" "Install with options and flexibility")
  
  if [ -z "$install_type" ]; then
    dialog --msgbox "No option selected. Exiting." 5 40
    exit 1
  fi
}

# Partition and Disk Selection
select_disk() {
  disk=$(lsblk -dn -o NAME,SIZE | grep -E 'sd|nvme' | awk '{print $1, $2}' | dialog --stdout --menu "Select Disk" 20 70 15)
  
  if [ -z "$disk" ]; then
    dialog --msgbox "No disk selected. Exiting." 5 40
    exit 1
  fi
}

# Partition creation
create_partitions() {
  dialog --infobox "Creating partitions on $disk..." 5 50
  # Partition logic goes here (handle both EFI and root)
  sgdisk --zap-all "$disk"
  # Create new partitions
  sgdisk -n 1:0:+300M -t 1:ef00 "$disk"
  sgdisk -n 2:0:0 -t 2:8300 "$disk"
}

# Handle Minimal Install
minimal_install() {
  # Default installs like base, sudo, ZSH, etc.
  pacstrap /mnt base linux linux-firmware sudo zsh
}

# Handle Custom Install
custom_install() {
  # Ask for additional packages (btrfs, zram, etc)
  packages=$(dialog --stdout --checklist "Select additional packages:" 15 60 5 \
    "btrfs" "Install Btrfs" off \
    "networkmanager" "Install NetworkManager" off \
    "zram" "Enable ZRAM" off)

  pacstrap /mnt base linux linux-firmware sudo zsh $packages
}

# Main Install Function
install_arch() {
  check_root
  check_uefi
  check_internet
  install_packages
  choose_install_type
  set_timezone
  select_disk
  create_partitions
  
  if [ "$install_type" == "Minimal" ]; then
    minimal_install
  else
    custom_install
  fi
  
  dialog --msgbox "Installation complete. Enjoy your Arch experience!" 7 50
}

install_arch
