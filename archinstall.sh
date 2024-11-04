#!/bin/bash

# Arch Linux Minimal Installation Script with Btrfs and rEFInd
# WARNING: This script will erase the selected disk.

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit
fi

# Install dialog if not already installed
if ! command -v dialog &> /dev/null; then
  pacman -Sy --noconfirm dialog
fi

# Clear the screen
clear

# Check for UEFI mode
if [ ! -d /sys/firmware/efi/efivars ]; then
  dialog --msgbox "Your system is not booted in UEFI mode.\nPlease reboot in UEFI mode to use this installer." 8 60
  clear
  exit 1
fi

# Check internet connection
if ! ping -c 1 archlinux.org &> /dev/null; then
  dialog --msgbox "Internet connection is required.\nPlease connect to the internet and rerun the installer." 7 60
  clear
  exit 1
fi

# Set time synchronization
timedatectl set-ntp true

# Welcome message
dialog --title "Arch Linux Minimal Installer" --msgbox "Welcome to the Arch Linux Minimal Installer." 8 60

# Disk selection
disk=$(dialog --stdout --title "Select Disk" --menu "Select the disk to install Arch Linux on:\nWARNING: All data on the disk will be erased!" 15 60 4 $(lsblk -dn -o NAME,SIZE | awk '{print "/dev/" $1 " " $2}'))
if [ -z "$disk" ]; then
  dialog --msgbox "No disk selected. Exiting." 5 40
  clear
  exit 1
fi

# Confirm disk selection
dialog --yesno "Are you sure you want to erase all data on $disk?" 7 50
if [ $? -ne 0 ]; then
  dialog --msgbox "Installation cancelled." 5 40
  clear
  exit 1
fi

# Recommend Btrfs partition layout
dialog --title "Partition Layout Recommendation" --msgbox "Recommended Btrfs partition layout:\n\n- EFI System Partition (ESP): /boot/efi\n- Btrfs subvolumes:\n  - @ mounted at /\n  - @home mounted at /home\n  - @pkg mounted at /var/cache/pacman/pkg\n  - @log mounted at /var/log\n  - @snapshots mounted at /.snapshots" 15 70

# Partitioning
dialog --infobox "Partitioning $disk..." 5 40
# Wipe the disk
sgdisk --zap-all $disk

# Create partitions
# Partition 1: EFI System Partition
sgdisk -n 1:0:+550M -t 1:ef00 $disk
# Partition 2: Root partition
sgdisk -n 2:0:0 -t 2:8300 $disk

# Get partition names
if [[ "$disk" == *"nvme"* ]]; then
  esp="${disk}p1"
  root_partition="${disk}p2"
else
  esp="${disk}1"
  root_partition="${disk}2"
fi

# Format partitions
dialog --infobox "Formatting partitions..." 5 40
mkfs.vfat -F32 $esp
mkfs.btrfs -f -L ArchLinux $root_partition

# Mount root partition
mount $root_partition /mnt

# Create Btrfs subvolumes
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@pkg
btrfs su cr /mnt/@log
btrfs su cr /mnt/@snapshots

# Unmount root partition
umount /mnt

# Mount subvolumes with options
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@ $root_partition /mnt
mkdir -p /mnt/{boot/efi,home,var/cache/pacman/pkg,var/log,.snapshots}
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@home $root_partition /mnt/home
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@pkg $root_partition /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@log $root_partition /mnt/var/log
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@snapshots $root_partition /mnt/.snapshots

# Mount EFI partition
mount $esp /mnt/boot/efi

# Detect CPU and offer to install microcode
cpu_vendor=$(lscpu | awk -F: '/Vendor ID/{gsub(/^[ \t]+/, "", $2); print $2}')
microcode_pkg=""
microcode_img=""
if [[ "$cpu_vendor" == "GenuineIntel" ]]; then
  dialog --yesno "CPU detected: Intel\nWould you like to install intel-ucode?" 7 60
  if [ $? -eq 0 ]; then
    microcode_pkg="intel-ucode"
    microcode_img="intel-ucode.img"
  fi
elif [[ "$cpu_vendor" == "AuthenticAMD" ]]; then
  dialog --yesno "CPU detected: AMD\nWould you like to install amd-ucode?" 7 60
  if [ $? -eq 0 ]; then
    microcode_pkg="amd-ucode"
    microcode_img="amd-ucode.img"
  fi
fi

# Offer to install btrfs-progs
dialog --yesno "Would you like to install btrfs-progs for Btrfs management?" 7 60
if [ $? -eq 0 ]; then
  btrfs_pkg="btrfs-progs"
else
  btrfs_pkg=""
fi

# Install base system
dialog --infobox "Installing base system..." 5 40
pacstrap /mnt base linux linux-firmware $microcode_pkg $btrfs_pkg

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Offer to install NetworkManager
dialog --yesno "Would you like to install NetworkManager for network management?" 7 60
if [ $? -eq 0 ]; then
  arch-chroot /mnt pacman -Sy --noconfirm networkmanager
  arch-chroot /mnt systemctl enable NetworkManager
fi

# Offer to install a text editor
editor_choice=$(dialog --stdout --title "Text Editor" --menu "Choose a text editor to install:" 10 50 3 \
  "nano" "Simple text editor" \
  "vim" "Vi Improved" \
  "emacs" "Extensible editor")
if [ -n "$editor_choice" ]; then
  arch-chroot /mnt pacman -Sy --noconfirm $editor_choice
fi

# Set root password
dialog --msgbox "You will now set the root password." 6 40
arch-chroot /mnt passwd

# Offer to create a standard user
dialog --yesno "Would you like to create a standard user?" 7 50
if [ $? -eq 0 ]; then
  username=$(dialog --stdout --inputbox "Enter username:" 8 40)
  if [ -n "$username" ]; then
    arch-chroot /mnt useradd -m $username
    dialog --msgbox "You will now set the password for $username." 6 50
    arch-chroot /mnt passwd $username
    # Install sudo and offer to add user to sudoers
    arch-chroot /mnt pacman -Sy --noconfirm sudo
    dialog --yesno "Would you like to grant $username sudo privileges?" 7 50
    if [ $? -eq 0 ]; then
      arch-chroot /mnt usermod -aG wheel $username
      arch-chroot /mnt sed -i '/^# %wheel ALL=(ALL) ALL$/s/^# //' /etc/sudoers
    fi
  else
    dialog --msgbox "No username entered. Skipping user creation." 5 50
  fi
fi

# Install rEFInd bootloader with Btrfs support and tweaks
dialog --infobox "Installing rEFInd bootloader..." 5 40
arch-chroot /mnt pacman -Sy --noconfirm refind
arch-chroot /mnt refind-install

# rEFInd configuration
# Modify refind.conf
arch-chroot /mnt sed -i 's/^#enable_mouse/enable_mouse/' /boot/efi/EFI/refind/refind.conf
arch-chroot /mnt sed -i 's/^#mouse_speed .*/mouse_speed 8/' /boot/efi/EFI/refind/refind.conf
arch-chroot /mnt sed -i 's/^#resolution .*/resolution max/' /boot/efi/EFI/refind/refind.conf
arch-chroot /mnt sed -i 's/^#extra_kernel_version_strings .*/extra_kernel_version_strings linux-hardened,linux-rt-lts,linux-zen,linux-lts,linux-rt,linux/' /boot/efi/EFI/refind/refind.conf

# Create refind_linux.conf with the specified options
partuuid=$(blkid -s PARTUUID -o value $root_partition)
initrd_line=""
if [ -n "$microcode_img" ]; then
  initrd_line="initrd=@\\boot\\$microcode_img initrd=@\\boot\\initramfs-%v.img"
else
  initrd_line="initrd=@\\boot\\initramfs-%v.img"
fi

cat << EOF > /mnt/boot/refind_linux.conf
"Boot with standard options"  "root=PARTUUID=$partuuid rw rootflags=subvol=@ $initrd_line"
EOF

# Copy refind_linux.conf to rEFInd directory
cp /mnt/boot/refind_linux.conf /mnt/boot/efi/EFI/refind/

# Finish
dialog --msgbox "Installation complete! You can now reboot into your new system." 6 50

# Unmount partitions
umount -R /mnt

# Offer to reboot
dialog --yesno "Would you like to reboot now?" 6 40
if [ $? -eq 0 ]; then
  reboot
else
  clear
  exit 0
fi
