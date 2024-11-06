#!/bin/bash

# Arch Linux Minimal Installation Script with Btrfs, rEFInd, ZRAM, and User Setup
# Version: v1.0.10 - Uses arch-chroot directly for chroot environment

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# Install necessary packages if not already installed
if ! command -v dialog &> /dev/null; then
  pacman -Sy --noconfirm dialog
fi

# Display script version
dialog --title "Arch Linux Minimal Installer - Version v1.0.10" --msgbox "You are using the latest version of the Arch Linux Minimal Installer script (v1.0.10).

This version includes all the features and fixes we've discussed, including proper chroot handling." 10 70

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

# Welcome message with extended information
dialog --title "Arch Linux Minimal Installer" --msgbox "Welcome to the Arch Linux Minimal Installer.\n\nThis installer provides a quick and easy minimal install for Arch Linux, setting up a base system that boots to a terminal." 12 70

# Ask if the user wants to use the default Btrfs subvolume scheme
dialog --yesno "The default Btrfs subvolume scheme is as follows:\n\n@ mounted at /mnt\n@home mounted at /mnt/home\n@pkg mounted at /mnt/var/cache/pacman/pkg\n@log mounted at /mnt/var/log\n@snapshots mounted at /mnt/.snapshots\n\nWould you like to use this scheme?" 15 70
if [ $? -ne 0 ]; then
  dialog --msgbox "Installation canceled. Exiting." 5 40
  clear
  exit 1
fi

# Disk selection
echo "[DEBUG] Prompting for disk selection"
disk=$(dialog --stdout --title "Select Disk" --menu "Select the disk to install Arch Linux on:" 15 60 4 $(lsblk -dn -o NAME,SIZE,TYPE | awk '$3=="disk" {print "/dev/" $1 " " $2}'))
if [ -z "$disk" ]; then
  dialog --msgbox "No disk selected. Exiting." 5 40
  clear
  exit 1
fi

# Detect existing partitions
existing_partitions=$(lsblk -o NAME,TYPE $disk | grep part)
if [ -n "$existing_partitions" ]; then
  dialog --yesno "Existing partitions detected on $disk. Would you like to destroy the current partitions and recreate them?" 7 60
  if [ $? -eq 0 ]; then
    echo "[DEBUG] Destroying existing partitions on $disk"
    sgdisk --zap-all $disk
    if [ $? -ne 0 ]; then
      dialog --msgbox "Failed to destroy partitions on $disk. Exiting." 5 40
      exit 1
    fi
  else
    dialog --msgbox "Installation canceled. Exiting." 5 40
    clear
    exit 1
  fi
fi

# Get partition names (after partitions are created)
if [[ "$disk" == *"nvme"* ]]; then
  esp="${disk}p1"
  root_partition="${disk}p2"
else
  esp="${disk}1"
  root_partition="${disk}2"
fi

# Prompt for hostname
echo "[DEBUG] Prompting for hostname"
hostname=$(dialog --stdout --inputbox "Enter a hostname for your system:" 8 40)
if [ -z "$hostname" ]; then
  dialog --msgbox "No hostname entered. Using default 'archlinux'." 6 50
  hostname="archlinux"
fi

# Prompt for timezone using dialog
echo "[DEBUG] Prompting for timezone"
available_regions=$(ls /usr/share/zoneinfo | grep -v 'posix\|right\|Etc\|SystemV\|Factory')
region=$(dialog --stdout --title "Select Region" --menu "Select your region:" 20 60 15 $(echo "$available_regions" | awk '{print $1, $1}'))
if [ -z "$region" ]; then
  dialog --msgbox "No region selected. Using 'UTC' as default." 6 50
  timezone="UTC"
else
  available_cities=$(ls /usr/share/zoneinfo/$region)
  city=$(dialog --stdout --title "Select City" --menu "Select your city:" 20 60 15 $(echo "$available_cities" | awk '{print $1, $1}'))
  if [ -z "$city" ]; then
    dialog --msgbox "No city selected. Using 'UTC' as default." 6 50
    timezone="UTC"
  else
    timezone="$region/$city"
  fi
fi

# Prompt for locale selection
echo "[DEBUG] Prompting for locale selection"
available_locales=$(awk '/^[a-z]/ {print $1}' /usr/share/i18n/SUPPORTED | sort)
locale_options=()
index=1
while IFS= read -r line; do
  locale_options+=("$index" "$line")
  index=$((index + 1))
done <<< "$available_locales"

selected_number=$(dialog --stdout --title "Select Locale" --menu "Select your locale:" 20 60 15 "${locale_options[@]}")
if [ -z "$selected_number" ]; then
  dialog --msgbox "No locale selected. Using 'en_US.UTF-8' as default." 6 50
  selected_locale="en_US.UTF-8"
else
  selected_locale=$(echo "$available_locales" | sed -n "${selected_number}p")
fi

# Prompt for root password with validation
echo "[DEBUG] Prompting for root password"
while true; do
  root_password=$(dialog --stdout --insecure --passwordbox "Enter a root password (minimum 6 characters):" 10 50)
  if [ -z "$root_password" ]; then
    dialog --msgbox "Password cannot be empty. Please try again." 6 50
    continue
  elif [ ${#root_password} -lt 6 ]; then
    dialog --msgbox "Password must be at least 6 characters long. Please try again." 6 60
    continue
  fi
  root_password_confirm=$(dialog --stdout --insecure --passwordbox "Confirm the root password:" 8 50)
  if [ "$root_password" != "$root_password_confirm" ]; then
    dialog --msgbox "Passwords do not match. Please try again." 6 50
  else
    break
  fi
done

# Prompt to create a new user account
dialog --yesno "Would you like to create a new user account?" 7 50
if [ $? -eq 0 ]; then
  create_user="yes"
  # Prompt for username
  while true; do
    username=$(dialog --stdout --inputbox "Enter the username for the new account:" 8 40)
    if [ -z "$username" ]; then
      dialog --msgbox "Username cannot be empty. Please try again." 6 50
    else
      break
    fi
  done

  # Prompt for user password with validation
  echo "[DEBUG] Prompting for user password"
  while true; do
    user_password=$(dialog --stdout --insecure --passwordbox "Enter a password for $username (minimum 6 characters):" 10 50)
    if [ -z "$user_password" ]; then
      dialog --msgbox "Password cannot be empty. Please try again." 6 50
      continue
    elif [ ${#user_password} -lt 6 ]; then
      dialog --msgbox "Password must be at least 6 characters long. Please try again." 6 60
      continue
    fi
    user_password_confirm=$(dialog --stdout --insecure --passwordbox "Confirm the password for $username:" 8 50)
    if [ "$user_password" != "$user_password_confirm" ]; then
      dialog --msgbox "Passwords do not match. Please try again." 6 50
    else
      break
    fi
  done

  # Prompt to grant sudo privileges
  dialog --yesno "Should the user '$username' have sudo privileges?" 7 50
  if [ $? -eq 0 ]; then
    grant_sudo="yes"
  else
    grant_sudo="no"
  fi
else
  create_user="no"
fi

# Offer to install btrfs-progs
echo "[DEBUG] Prompting for Btrfs tools installation"
dialog --yesno "Would you like to install btrfs-progs for Btrfs management?" 7 60
if [ $? -eq 0 ]; then
  btrfs_pkg="btrfs-progs"
else
  btrfs_pkg=""
fi

# Offer to install NetworkManager
echo "[DEBUG] Prompting for NetworkManager installation"
dialog --yesno "Would you like to install NetworkManager for network management?" 7 60
if [ $? -eq 0 ]; then
  networkmanager_pkg="networkmanager"
else
  networkmanager_pkg=""
fi

# Offer to enable ZRAM
echo "[DEBUG] Prompting for ZRAM enablement"
dialog --yesno "Would you like to enable ZRAM for swap?" 7 50
if [ $? -eq 0 ]; then
  zram_pkg="zram-generator"
else
  zram_pkg=""
fi

# Detect CPU and offer to install microcode
echo "[DEBUG] Detecting CPU vendor"
cpu_vendor=$(grep -m1 -E 'vendor_id|Vendor ID' /proc/cpuinfo | awk '{print $3}' | tr '[:upper:]' '[:lower:]')
microcode_pkg=""
microcode_img=""

if [[ "$cpu_vendor" == *"intel"* ]]; then
  dialog --yesno "CPU detected: Intel\nWould you like to install intel-ucode?" 7 60
  if [ $? -eq 0 ]; then
    microcode_pkg="intel-ucode"
    microcode_img="intel-ucode.img"
  fi
elif [[ "$cpu_vendor" == *"amd"* ]]; then
  dialog --yesno "CPU detected: AMD\nWould you like to install amd-ucode?" 7 60
  if [ $? -eq 0 ]; then
    microcode_pkg="amd-ucode"
    microcode_img="amd-ucode.img"
  fi
else
  dialog --msgbox "CPU vendor not detected. Microcode will not be installed." 6 60
fi

# All dialogs are now completed before installation starts

# Create partitions
echo "[DEBUG] Creating partitions on $disk"
# Partition 1: EFI System Partition
sgdisk -n 1:0:+300M -t 1:ef00 $disk
if [ $? -ne 0 ]; then
  dialog --msgbox "Failed to create EFI partition on $disk. Exiting." 5 40
  exit 1
fi

# Wait for the system to recognize the partition changes
sleep 5

# Partition 2: Root partition
sgdisk -n 2:0:0 -t 2:8300 $disk
if [ $? -ne 0 ]; then
  dialog --msgbox "Failed to create root partition on $disk. Exiting." 5 40
  exit 1
fi

# Wait for the system to recognize the partition changes
sleep 5

# Format partitions
echo "[DEBUG] Formatting partitions"
dialog --infobox "Formatting partitions..." 5 40
mkfs.vfat -F32 -I $esp
if [ $? -ne 0 ]; then
  dialog --msgbox "Failed to format EFI partition. Exiting." 5 40
  exit 1
fi
mkfs.btrfs -f -L Arch $root_partition
if [ $? -ne 0 ]; then
  dialog --msgbox "Failed to format root partition. Exiting." 5 40
  exit 1
fi

# Mount root partition
echo "[DEBUG] Mounting root partition $root_partition"
mount $root_partition /mnt
if [ $? -ne 0 ]; then
  dialog --msgbox "Failed to mount root partition. Exiting." 5 40
  exit 1
fi

# Create Btrfs subvolumes
echo "[DEBUG] Creating Btrfs subvolumes"
btrfs su cr /mnt/@
if [ $? -ne 0 ]; then
  dialog --msgbox "Failed to create @ subvolume. Exiting." 5 40
  exit 1
fi
btrfs su cr /mnt/@home
btrfs su cr /mnt/@pkg
btrfs su cr /mnt/@log
btrfs su cr /mnt/@snapshots

# Unmount root partition
echo "[DEBUG] Unmounting root partition"
umount /mnt

# Mount subvolumes with options
mount_options="noatime,compress=zstd,discard=async,space_cache=v2"
echo "[DEBUG] Mounting Btrfs subvolumes"
mount -o $mount_options,subvol=@ $root_partition /mnt
if [ $? -ne 0 ]; then
  dialog --msgbox "Failed to mount root subvolume. Exiting." 5 40
  exit 1
fi
mkdir -p /mnt/{boot/efi,home,var/cache/pacman/pkg,var/log,.snapshots}
mount -o $mount_options,subvol=@home $root_partition /mnt/home
mount -o $mount_options,subvol=@pkg $root_partition /mnt/var/cache/pacman/pkg
mount -o $mount_options,subvol=@log $root_partition /mnt/var/log
mount -o $mount_options,subvol=@snapshots $root_partition /mnt/.snapshots

# Mount EFI partition
echo "[DEBUG] Mounting EFI partition $esp"
mount $esp /mnt/boot/efi
if [ $? -ne 0 ]; then
  dialog --msgbox "Failed to mount EFI partition. Exiting." 5 40
  exit 1
fi

# Install base system
echo "[DEBUG] Installing base system"
dialog --infobox "Installing base system..." 5 40
pacstrap /mnt base linux linux-firmware $microcode_pkg $btrfs_pkg $zram_pkg $networkmanager_pkg
if [ $? -ne 0 ]; then
  dialog --msgbox "Failed to install base system. Exiting." 5 40
  exit 1
fi

# Generate fstab
echo "[DEBUG] Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab
if [ $? -ne 0 ]; then
  dialog --msgbox "Failed to generate fstab. Exiting." 5 40
  exit 1
fi

# Set up variables for chroot
export microcode_img
export hostname
export timezone
export selected_locale
export zram_pkg
export root_password
export create_user
export username
export user_password
export grant_sudo

# Chroot into the new system for configurations
echo "[DEBUG] Entering chroot to configure the new system"
arch-chroot /mnt /bin/bash <<EOF
# Set the timezone
echo "[DEBUG] Setting timezone to $timezone"
ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
hwclock --systohc

# Set the hostname
echo "[DEBUG] Setting hostname to $hostname"
echo "$hostname" > /etc/hostname

# Configure /etc/hosts
echo "[DEBUG] Configuring /etc/hosts"
cat <<EOL > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain $hostname
EOL

# Generate locales
echo "[DEBUG] Generating locales"
echo "$selected_locale UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$selected_locale" > /etc/locale.conf

# Configure ZRAM if enabled
if [ -n "$zram_pkg" ]; then
  echo "[DEBUG] Configuring ZRAM"
  cat <<EOM > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOM
fi

# Set the root password
echo "[DEBUG] Setting root password"
echo "root:$root_password" | chpasswd

# Clear the root password variable for security
unset root_password

# Create user account if requested
if [ "$create_user" == "yes" ]; then
  echo "[DEBUG] Creating user account: $username"
  useradd -m "$username"
  echo "$username:$user_password" | chpasswd
  unset user_password

  if [ "$grant_sudo" == "yes" ]; then
    echo "[DEBUG] Granting sudo privileges to $username"
    pacman -Sy --noconfirm sudo
    usermod -aG wheel "$username"
    sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
  fi
fi

# Ask if the user wants to use bash or install zsh
echo "[DEBUG] Prompting for shell selection"
if [ -f /bin/dialog ]; then
  dialog --yesno "Would you like to use Zsh as your default shell instead of Bash?" 7 50
  if [ \$? -eq 0 ]; then
    pacman -Sy --noconfirm zsh
    chsh -s /bin/zsh
    if [ "$create_user" == "yes" ]; then
      chsh -s /bin/zsh "$username"
    fi
  fi
else
  echo "Dialog not found. Skipping shell selection."
fi

EOF

# Clear sensitive variables
unset root_password
unset user_password

# Install rEFInd bootloader with Btrfs support and tweaks
echo "[DEBUG] Installing rEFInd bootloader"
dialog --infobox "Installing rEFInd bootloader..." 5 40
arch-chroot /mnt pacman -Sy --noconfirm refind
arch-chroot /mnt refind-install
if [ $? -ne 0 ]; then
  dialog --msgbox "Failed to install rEFInd. Exiting." 5 40
  exit 1
fi

# rEFInd configuration
echo "[DEBUG] Modifying rEFInd configuration"
arch-chroot /mnt sed -i 's/^#enable_mouse/enable_mouse/' /boot/efi/EFI/refind/refind.conf
arch-chroot /mnt sed -i 's/^#mouse_speed .*/mouse_speed 8/' /boot/efi/EFI/refind/refind.conf
arch-chroot /mnt sed -i 's/^#resolution .*/resolution max/' /boot/efi/EFI/refind/refind.conf
arch-chroot /mnt sed -i 's/^#extra_kernel_version_strings .*/extra_kernel_version_strings linux-hardened,linux-rt-lts,linux-zen,linux-lts,linux-rt,linux/' /boot/efi/EFI/refind/refind.conf

# Create refind_linux.conf with the specified options
echo "[DEBUG] Creating refind_linux.conf"
partuuid=$(blkid -s PARTUUID -o value $root_partition)
initrd_line=""
if [ -n "$microcode_img" ]; then
  initrd_line="initrd=\\@\\boot\\$microcode_img initrd=\\@\\boot\\initramfs-%v.img"
else
  initrd_line="initrd=\\@\\boot\\initramfs-%v.img"
fi

cat << EOF > /mnt/boot/refind_linux.conf
"Boot with standard options"  "root=PARTUUID=$partuuid rw rootflags=subvol=@ $initrd_line"
"Boot using fallback initramfs"  "root=PARTUUID=$partuuid rw rootflags=subvol=@ initrd=\\@\\boot\\initramfs-%v-fallback.img"
"Boot to terminal"  "root=PARTUUID=$partuuid rw rootflags=subvol=@ initrd=\\@\\boot\\initramfs-%v.img systemd.unit=multi-user.target"
EOF

# Copy refind_linux.conf to rEFInd directory
echo "[DEBUG] Copying refind_linux.conf to rEFInd directory"
cp /mnt/boot/refind_linux.conf /mnt/boot/efi/EFI/refind/

# Finish installation
dialog --yesno "Installation complete! Would you like to reboot now or drop to the terminal for additional configuration?

Select 'No' to drop to the terminal." 10 70
if [ $? -eq 0 ]; then
  # Reboot the system
  umount -R /mnt
  reboot
else
  # Clear the screen
  clear
  # Drop into the chroot environment
  echo "[DEBUG] Dropping into chroot environment for additional configuration"
  echo "Type 'exit' to leave the chroot environment and complete the installation."
  arch-chroot /mnt /bin/bash
fi
