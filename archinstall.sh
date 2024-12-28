#!/bin/bash

#===========================================================
# Arch Linux Installation Script
# - Unmounts & disables swap on selected disk
# - Wipes existing partitions and signatures thoroughly
# - Supports ext4 or BTRFS auto partitioning and manual
#===========================================================

# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Exiting."
  exit 1
fi

#-----------------------------------------------------------
# Safely prompt user for input (stdout > /dev/tty)
#-----------------------------------------------------------
prompt() {
  local message="$1"
  local varname="$2"
  echo "$message" > /dev/tty
  read -r "$varname" < /dev/tty
}

#-----------------------------------------------------------
# List all non-loop, non-ROM block devices for user selection
#-----------------------------------------------------------
create_disk_menu() {
  echo "Available Disks (excluding loop and CD-ROM):" > /dev/tty
  lsblk -d -p -n -o NAME,SIZE,TYPE \
    | grep -E "disk" \
    | grep -v loop \
    | nl \
    > /dev/tty

  prompt "Enter the number corresponding to your disk: " disk_number

  selected_disk=$(lsblk -d -p -n -o NAME,TYPE \
    | grep disk \
    | grep -v loop \
    | awk '{print $1}' \
    | sed -n "${disk_number}p")

  if [[ -z "$selected_disk" ]]; then
    echo "Invalid selection. Please try again." > /dev/tty
    create_disk_menu
  else
    echo "Selected disk: $selected_disk" > /dev/tty
  fi
}

#-----------------------------------------------------------
# Prompt user for partition scheme
#-----------------------------------------------------------
create_partition_menu() {
  echo "Partitioning Scheme Options:" > /dev/tty
  echo "1) Automatic partitioning (ext4)" > /dev/tty
  echo "2) Automatic partitioning (BTRFS)" > /dev/tty
  echo "3) Manual partitioning (cfdisk)" > /dev/tty

  prompt "Enter your choice (1-3): " choice
  case "$choice" in
    1) partition_choice="auto_ext4" ;;
    2) partition_choice="auto_btrfs" ;;
    3) partition_choice="manual" ;;
    *) 
       echo "Invalid choice. Try again." > /dev/tty
       create_partition_menu
       ;;
  esac
}

#-----------------------------------------------------------
# For a disk like /dev/nvme0n1, we must append 'p' for partition
# For /dev/sda or /dev/vda, just append the digit
#-----------------------------------------------------------
get_partition_name() {
  local disk="$1"
  local part_num="$2"

  # Matches /dev/nvme<number>n<number>, possibly multi-digit
  if [[ "$disk" =~ nvme[0-9]+n[0-9]+$ ]]; then
    echo "${disk}p${part_num}"
  else
    echo "${disk}${part_num}"
  fi
}

#-----------------------------------------------------------
# Unmount & swapoff everything on $selected_disk
# Then wipe out partition table (GPT) on that disk
#-----------------------------------------------------------
wipe_partitions() {
  echo "Wiping existing partitions on $selected_disk..." > /dev/tty

  # Unmount anything on this disk and disable swap
  for part in $(lsblk -n -o NAME "$selected_disk"); do
    if [[ -b "/dev/$part" ]]; then
      umount -R "/dev/$part" 2>/dev/null || true
      swapoff "/dev/$part" 2>/dev/null || true
    fi
  done

  # Destroy all FS signatures, then make new GPT label
  wipefs -a "$selected_disk"
  parted -s "$selected_disk" mklabel gpt
  echo "GPT partition table created on $selected_disk" > /dev/tty
}

#-----------------------------------------------------------
# Return swap in MiB as half the total system RAM
#-----------------------------------------------------------
calculate_swap_size() {
  local ram_kB
  ram_kB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  # half of RAM in MiB
  local swap_mib=$(( ram_kB / 2 / 1024 ))
  echo "$swap_mib"
}

#-----------------------------------------------------------
# Automatic or manual partitioning.
#   auto_ext4  -> (esp, swap, root ext4)
#   auto_btrfs -> (esp, swap, root btrfs)
#   manual     -> open cfdisk, user does everything else
#-----------------------------------------------------------
perform_partitioning() {
  local disk="$1"
  local choice="$2"

  local swap_size
  swap_size=$(calculate_swap_size)

  case "$choice" in
    "auto_ext4")
        echo "Performing automatic partitioning (ext4) on $disk" > /dev/tty

        # Partition layout
        local esp=$(get_partition_name "$disk" 1)
        local swp=$(get_partition_name "$disk" 2)
        local root=$(get_partition_name "$disk" 3)

        parted -s "$disk" mkpart primary fat32 1MiB 513MiB
        parted -s "$disk" set 1 esp on
        parted -s "$disk" mkpart primary linux-swap 513MiB "$((513 + swap_size))MiB"
        parted -s "$disk" mkpart primary ext4 "$((513 + swap_size))MiB" 100%

        partprobe "$disk"

        # Wipe leftover signatures on each partition (just in case)
        wipefs -a "$esp"
        wipefs -a "$swp"
        wipefs -a "$root"

        # Format with force flags where relevant
        mkfs.fat -F32 -I "$esp"
        mkswap "$swp"
        swapon "$swp"
        mkfs.ext4 -F "$root"

        # Mount
        mount "$root" /mnt
        mkdir -p /mnt/efi
        mount "$esp" /mnt/efi
        ;;
    
    "auto_btrfs")
        echo "Performing automatic partitioning (BTRFS) on $disk" > /dev/tty

        local esp=$(get_partition_name "$disk" 1)
        local swp=$(get_partition_name "$disk" 2)
        local root=$(get_partition_name "$disk" 3)

        parted -s "$disk" mkpart primary fat32 1MiB 513MiB
        parted -s "$disk" set 1 esp on
        parted -s "$disk" mkpart primary linux-swap 513MiB "$((513 + swap_size))MiB"
        parted -s "$disk" mkpart primary btrfs "$((513 + swap_size))MiB" 100%

        partprobe "$disk"

        # Wipe leftover signatures
        wipefs -a "$esp"
        wipefs -a "$swp"
        wipefs -a "$root"

        mkfs.fat -F32 -I "$esp"
        mkswap "$swp"
        swapon "$swp"
        mkfs.btrfs -f "$root"

        # Create subvolumes
        mount "$root" /mnt
        btrfs subvolume create /mnt/@
        btrfs subvolume create /mnt/@home
        btrfs subvolume create /mnt/@log
        btrfs subvolume create /mnt/@pkg
        btrfs subvolume create /mnt/@snapshots
        umount /mnt

        # Remount subvolumes
        mount -o subvol=@,compress=zstd,noatime "$root" /mnt
        mkdir -p /mnt/{efi,home,var/log,var/cache/pacman/pkg,.snapshots}
        mount -o subvol=@home,compress=zstd,noatime "$root" /mnt/home
        mount -o subvol=@log,compress=zstd,noatime "$root" /mnt/var/log
        mount -o subvol=@pkg,compress=zstd,noatime "$root" /mnt/var/cache/pacman/pkg
        mount -o subvol=@snapshots,compress=zstd,noatime "$root" /mnt/.snapshots
        mount "$esp" /mnt/efi
        ;;
    
    "manual")
        echo "Launching cfdisk for manual partitioning on $disk..." > /dev/tty
        cfdisk "$disk"
        ;;
  esac
}

#-----------------------------------------------------------
# Installs Arch base system into /mnt
#-----------------------------------------------------------
install_base_system() {
  if ! mountpoint -q /mnt; then
    echo "ERROR: /mnt is not mounted. Cannot install base system." > /dev/tty
    return 1
  fi

  # Prompt user if they want to use zsh
  prompt "Do you want to use zsh as your default shell? (yes/no): " use_zsh

  # Check if BTRFS is chosen and include btrfs-progs
  if [[ "$partition_choice" == "auto_btrfs" ]]; then
    if [[ "$use_zsh" =~ ^[Yy][Ee][Ss]|[Yy]$ ]]; then
      echo "Installing base system (base, linux, linux-firmware, sudo, btrfs-progs, zsh)..." > /dev/tty
      pacstrap -K /mnt base linux linux-firmware sudo btrfs-progs zsh
    else
      echo "Installing base system (base, linux, linux-firmware, sudo, btrfs-progs)..." > /dev/tty
      pacstrap -K /mnt base linux linux-firmware sudo btrfs-progs
    fi
  else
    if [[ "$use_zsh" =~ ^[Yy][Ee][Ss]|[Yy]$ ]]; then
      echo "Installing base system (base, linux, linux-firmware, sudo, zsh)..." > /dev/tty
      pacstrap -K /mnt base linux linux-firmware sudo zsh
    else
      echo "Installing base system (base, linux, linux-firmware, sudo)..." > /dev/tty
      pacstrap -K /mnt base linux linux-firmware sudo
    fi
  fi

  # Enable sudo for the wheel group
  sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers

  genfstab -U /mnt >> /mnt/etc/fstab
}

#-----------------------------------------------------------
# Installs & enables dhcpcd in chroot
#-----------------------------------------------------------
setup_network() {
  if ! mountpoint -q /mnt; then
    echo "ERROR: /mnt is not mounted. Cannot configure network." > /dev/tty
    return 1
  fi
  echo "Setting up minimal network configuration..." > /dev/tty
  arch-chroot /mnt pacman -S --noconfirm networkmanager
  arch-chroot /mnt systemctl enable NetworkManager.service
}

#-----------------------------------------------------------
# Configure locale, hostname, timezone, root password,
# and GRUB bootloader
#-----------------------------------------------------------
configure_system() {
  if ! mountpoint -q /mnt; then
    echo "ERROR: /mnt is not mounted. Cannot configure system." > /dev/tty
    return 1
  fi
  echo "Configuring system..." > /dev/tty

  # Some predefined locales
  locales=(
    "en_US.UTF-8 UTF-8"
    "en_GB.UTF-8 UTF-8"
    "fr_FR.UTF-8 UTF-8"
    "de_DE.UTF-8 UTF-8"
  )

  echo "Available Locales:" > /dev/tty
  for i in "${!locales[@]}"; do
    echo "$((i + 1)). ${locales[$i]}" > /dev/tty
  done

  while :; do
    prompt "Select your locale (1-${#locales[@]}): " locale_choice
    if [[ "$locale_choice" =~ ^[1-${#locales[@]}]$ ]]; then
      selected_locale="${locales[$((locale_choice - 1))]}"
      break
    else
      echo "Invalid choice. Try again." > /dev/tty
    fi
  done

  echo "$selected_locale" > /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
  echo "LANG=$(echo "$selected_locale" | awk '{print $1}')" > /mnt/etc/locale.conf

  # Hostname
  prompt "Enter your desired hostname: " hostname
  echo "$hostname" > /mnt/etc/hostname

  # /etc/hosts
  {
    echo "127.0.0.1    localhost"
    echo "::1          localhost"
    echo "127.0.1.1    $hostname.localdomain $hostname"
  } > /mnt/etc/hosts

  # Timezone (example using ipapi)
  arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$(curl -s https://ipapi.co/timezone)" /etc/localtime
  arch-chroot /mnt hwclock --systohc

  # Root password
  echo "Set the root password (you will be prompted in chroot):" > /dev/tty
  arch-chroot /mnt passwd

  # Bootloader
  echo "Installing GRUB bootloader..." > /dev/tty
  arch-chroot /mnt pacman -S --noconfirm grub efibootmgr
  arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

#-----------------------------------------------------------
# Main
#-----------------------------------------------------------
main() {
  create_disk_menu
  wipe_partitions
  create_partition_menu
  perform_partitioning "$selected_disk" "$partition_choice"

  # If user used manual partitioning, they must do their own mkfs & mount
  install_base_system || exit 1

  setup_network
  configure_system
  echo "Installation complete! You can now reboot." > /dev/tty
}

main
