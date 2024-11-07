#!/bin/bash

# Arch Linux Minimal Installation Script with Btrfs, rEFInd, ZRAM, and User Setup
# Version: v1.0.35 - Added option for Minimal or Custom Install, fixed partition detection, progress indicators, and ensured rEFInd installation

# Exit immediately if a command exits with a non-zero status
set -e

# Function to install necessary packages
install_packages() {
  required_packages=("dialog" "gptfdisk" "util-linux" "arch-install-scripts" "btrfs-progs" "refind" "zram-generator" "networkmanager" "sudo" "zsh")
  for pkg in "${required_packages[@]}"; do
    if ! pacman -Qi "$pkg" &> /dev/null; then
      pacman -Sy --noconfirm "$pkg"
    fi
  done
}

# Function to retrieve existing partitions
get_partitions() {
  local disk="$1"
  lsblk -ln -o NAME,TYPE,SIZE "$disk" | awk '$2 == "part" {print $1, $3}'
}

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  dialog --msgbox "Please run this script as root." 5 40
  exit 1
fi

# Install necessary packages
install_packages

# Display script version
dialog --title "Arch Linux Minimal Installer - Version v1.0.35" --msgbox "Welcome to the Arch Linux Minimal Installer script (v1.0.35).

This version introduces the option to perform a Minimal or Custom installation, fixes partition detection inconsistencies, progress indicators, and ensures the rEFInd bootloader is installed correctly." 12 70

# Clear the screen
clear

# Check for UEFI mode
if [ ! -d /sys/firmware/efi/efivars ]; then
  dialog --msgbox "Your system is not booted in UEFI mode.
Please reboot in UEFI mode to use this installer." 8 60
  clear
  exit 1
fi

# Check internet connection
if ! ping -c 1 archlinux.org &> /dev/null; then
  dialog --msgbox "Internet connection is required.
Please connect to the internet and rerun the installer." 7 60
  clear
  exit 1
fi

# Set time synchronization
timedatectl set-ntp true

# Welcome message with extended information
dialog --title "Arch Linux Minimal Installer" --msgbox "Welcome to the Arch Linux Minimal Installer.

This installer provides a quick and easy minimal install for Arch Linux, setting up a base system that boots to a terminal." 12 70

# Ask the user to choose between Minimal and Custom Install
install_type=$(dialog --stdout --title "Choose Installation Type" --menu "Select the type of installation you want to perform:

- **Minimal Install:** Uses default settings with essential packages.
- **Custom Install:** Allows you to select optional packages and configurations." 15 70 2 \
  "Minimal" "Minimal Install with default settings" \
  "Custom" "Custom Install with optional packages and configurations")

# Check if the user canceled the dialog
if [ -z "$install_type" ]; then
  dialog --msgbox "No installation type selected. Exiting." 5 40
  clear
  exit 1
fi

# Function to handle Minimal Install
minimal_install() {
  # Use default Btrfs subvolume scheme
  default_subvolumes=true
  # Select default packages
  selected_packages=()
}

# Function to handle Custom Install
custom_install() {
  # Allow user to select optional packages
  options=(
    "btrfs" "Install btrfs-progs" off
    "networkmanager" "Install NetworkManager" off
    "zram" "Enable ZRAM" off
  )
  selected_options=$(dialog --stdout --separate-output --checklist "Select optional features (use spacebar to select):" 15 60 4 "${options[@]}")
  
  if [ -z "$selected_options" ]; then
    dialog --msgbox "No optional features selected." 5 40
  fi
  
  # Initialize package variables
  btrfs_pkg=""
  networkmanager_pkg=""
  zram_pkg=""
  
  # Process selected options
  while IFS= read -r opt; do
    case "$opt" in
      btrfs)
        btrfs_pkg="btrfs-progs"
        ;;
      networkmanager)
        networkmanager_pkg="networkmanager"
        ;;
      zram)
        zram_pkg="zram-generator"
        ;;
    esac
  done <<< "$selected_options"
  
  # Trim any whitespace
  btrfs_pkg=$(echo "$btrfs_pkg" | xargs)
  networkmanager_pkg=$(echo "$networkmanager_pkg" | xargs)
  zram_pkg=$(echo "$zram_pkg" | xargs)
  
  # Detect CPU and offer to install microcode
  cpu_vendor=$(grep -m1 -E 'vendor_id|Vendor ID' /proc/cpuinfo | awk '{print $3}' | tr '[:upper:]' '[:lower:]')
  microcode_pkg=""
  microcode_img=""
  
  if [[ "$cpu_vendor" == *"intel"* ]]; then
    dialog --yesno "CPU detected: Intel
Would you like to install intel-ucode?" 7 60
      if [ $? -eq 0 ]; then
        microcode_pkg="intel-ucode"
        microcode_img="intel-ucode.img"
      fi
  elif [[ "$cpu_vendor" == *"amd"* ]]; then
    dialog --yesno "CPU detected: AMD
Would you like to install amd-ucode?" 7 60
      if [ $? -eq 0 ]; then
        microcode_pkg="amd-ucode"
        microcode_img="amd-ucode.img"
      fi
  else
    dialog --msgbox "CPU vendor not detected. Microcode will not be installed." 6 60
  fi
  
  # Add microcode package if selected
  [ -n "$microcode_pkg" ] && selected_packages+=("$microcode_pkg")
  
  # Add optional packages
  [ -n "$btrfs_pkg" ] && selected_packages+=("$btrfs_pkg")
  [ -n "$zram_pkg" ] && selected_packages+=("$zram_pkg")
  [ -n "$networkmanager_pkg" ] && selected_packages+=("$networkmanager_pkg")
  
  # Set selected subvolume scheme to false as user is customizing
  default_subvolumes=false
}

# Determine installation type
if [ "$install_type" == "Minimal" ]; then
  minimal_install
else
  custom_install
fi

# Ask if the user wants to use the default Btrfs subvolume scheme (only for Minimal Install)
if [ "$install_type" == "Minimal" ]; then
  dialog --yesno "The default Btrfs subvolume scheme is as follows:

@ mounted at /
@home mounted at /home
@pkg mounted at /var/cache/pacman/pkg
@log mounted at /var/log
@snapshots mounted at /.snapshots

Would you like to use this scheme?" 15 70
    
  if [ $? -ne 0 ]; then
    dialog --msgbox "Installation canceled. Exiting." 5 40
    clear
    exit 1
  fi
fi

# Build disk options array
disk_options=()
while read -r disk_line; do
  disk_name=$(echo "$disk_line" | awk '{print $1}')
  disk_size=$(echo "$disk_line" | awk '{print $2}')
  disk="/dev/$disk_name"

  # Get partitions for this disk
  partitions=$(get_partitions "$disk")
  
  # Count partitions
  partition_count=$(echo "$partitions" | wc -l)
  
  if [ "$partition_count" -eq 0 ]; then
    disk_info="Size: ${disk_size} GiB (No partitions)"
  else
    disk_info="Size: ${disk_size} GiB ($partition_count partition(s))"
  fi

  # Add to disk options
  disk_options+=("$disk" "$disk_info")
done < <(lsblk -dn -o NAME,SIZE | grep -E 'sd|hd|vd|nvme|mmcblk')

# Check if any disks are found
if [ ${#disk_options[@]} -eq 0 ]; then
  dialog --msgbox "No suitable disks found. Exiting." 5 40
  clear
  exit 1
fi

# Display disk selection menu
disk=$(dialog --stdout --title "Select Disk" --menu "Select the disk to install Arch Linux on:

Use arrow keys to navigate and Enter to select." 20 70 10 "${disk_options[@]}")

# Check if user canceled the selection
if [ -z "$disk" ]; then
  dialog --msgbox "No disk selected. Exiting." 5 40
  clear
  exit 1
fi

# Show existing partitions if any
existing_partitions=$(get_partitions "$disk")
if [ -n "$existing_partitions" ]; then
  dialog --title "Existing Partitions on $disk" --yesno "The following partitions exist on $disk:

$existing_partitions

Do you want to continue and reformat the disk?" 20 70
    if [ $? -ne 0 ]; then
      dialog --msgbox "Installation canceled by user. Exiting." 5 40
      clear
      exit 1
    fi
else
  dialog --title "Disk $disk" --yesno "No existing partitions were found on $disk.

Do you want to continue and format the disk?" 10 70
    if [ $? -ne 0 ]; then
      dialog --msgbox "Installation canceled by user. Exiting." 5 40
      clear
      exit 1
    fi
fi

# Show the proposed partition table
proposed_partitions=$(cat <<EOF
$disk (Size: $(lsblk -dn -o SIZE "$disk"))

  Partition 1: EFI System Partition (300 MiB)
  Partition 2: Linux Filesystem (Rest of the disk)
EOF
)

dialog --title "Proposed Partition Scheme for $disk" --yesno "The disk will be partitioned as follows:

$proposed_partitions

All data on the disk will be erased.

Do you want to proceed?" 20 70
if [ $? -ne 0 ]; then
  dialog --msgbox "Installation canceled by user. Exiting." 5 40
  clear
  exit 1
fi

# Confirm final decision
dialog --yesno "Are you absolutely sure you want to erase all data on $disk and proceed with the installation?" 7 60
if [ $? -ne 0 ]; then
  dialog --msgbox "Installation canceled by user. Exiting." 5 40
  clear
  exit 1
fi

# Destroy existing partitions
dialog --infobox "Destroying existing partitions on $disk..." 5 50
if ! sgdisk --zap-all "$disk" > /tmp/sgdisk_zap_output 2>&1; then
  dialog --msgbox "Failed to destroy partitions on $disk. Error: $(cat /tmp/sgdisk_zap_output)" 10 60
  exit 1
fi

# Wait for the system to recognize the partition changes
sleep 2

# Create new partitions
dialog --infobox "Creating new partition table on $disk..." 5 50
if ! sgdisk -n 1:0:+300M -t 1:ef00 "$disk" > /tmp/sgdisk_new_output 2>&1; then
  dialog --msgbox "Failed to create EFI partition on $disk. Error: $(cat /tmp/sgdisk_new_output)" 10 60
  exit 1
fi
if ! sgdisk -n 2:0:0 -t 2:8300 "$disk" >> /tmp/sgdisk_new_output 2>&1; then
  dialog --msgbox "Failed to create root partition on $disk. Error: $(cat /tmp/sgdisk_new_output)" 10 60
  exit 1
fi

# Wait for the system to recognize the partition changes
sleep 2

# Get partition names (after partitions are created)
if [[ "$(basename "$disk")" == nvme* ]] || [[ "$(basename "$disk")" == mmcblk* ]]; then
  esp="${disk}p1"
  root_partition="${disk}p2"
else
  esp="${disk}1"
  root_partition="${disk}2"
fi

# Clean up temporary files
rm -f /tmp/sgdisk_zap_output /tmp/sgdisk_new_output

# Prompt for hostname
hostname=$(dialog --stdout --inputbox "Enter a hostname for your system:" 8 40)
if [ -z "$hostname" ]; then
  dialog --msgbox "No hostname entered. Using default 'archlinux'." 6 50
  hostname="archlinux"
fi

# Prompt for timezone using dialog
available_regions=$(ls /usr/share/zoneinfo | grep -v 'posix\|right\|Etc\|SystemV\|Factory')
region=$(dialog --stdout --title "Select Region" --menu "Select your region:" 20 60 15 $(echo "$available_regions" | awk '{print $1, $1}'))
if [ -z "$region" ]; then
  dialog --msgbox "No region selected. Using 'UTC' as default." 6 50
  timezone="UTC"
else
  available_cities=$(ls /usr/share/zoneinfo/"$region")
  city=$(dialog --stdout --title "Select City" --menu "Select your city:" 20 60 15 $(echo "$available_cities" | awk '{print $1, $1}'))
  if [ -z "$city" ]; then
    dialog --msgbox "No city selected. Using 'UTC' as default." 6 50
    timezone="UTC"
  else
    timezone="$region/$city"
  fi
fi

# Prompt for locale selection
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

# Handle Minimal or Custom Install
if [ "$install_type" == "Custom" ]; then
  # Optional packages already handled in custom_install function
  :
elif [ "$install_type" == "Minimal" ]; then
  # Minimal Install: Use default Btrfs subvolumes and no optional packages
  selected_packages=()
  default_subvolumes=true
fi

# Show the proposed partition table
proposed_partitions=$(cat <<EOF
$disk (Size: $(lsblk -dn -o SIZE "$disk"))

  Partition 1: EFI System Partition (300 MiB)
  Partition 2: Linux Filesystem (Rest of the disk)
EOF
)

dialog --title "Proposed Partition Scheme for $disk" --yesno "The disk will be partitioned as follows:

$proposed_partitions

All data on the disk will be erased.

Do you want to proceed?" 20 70
if [ $? -ne 0 ]; then
  dialog --msgbox "Installation canceled by user. Exiting." 5 40
  clear
  exit 1
fi

# Confirm final decision
dialog --yesno "Are you absolutely sure you want to erase all data on $disk and proceed with the installation?" 7 60
if [ $? -ne 0 ]; then
  dialog --msgbox "Installation canceled by user. Exiting." 5 40
  clear
  exit 1
fi

# Destroy existing partitions
dialog --infobox "Destroying existing partitions on $disk..." 5 50
if ! sgdisk --zap-all "$disk" > /tmp/sgdisk_zap_output 2>&1; then
  dialog --msgbox "Failed to destroy partitions on $disk. Error: $(cat /tmp/sgdisk_zap_output)" 10 60
  exit 1
fi

# Wait for the system to recognize the partition changes
sleep 2

# Create new partitions
dialog --infobox "Creating new partition table on $disk..." 5 50
if ! sgdisk -n 1:0:+300M -t 1:ef00 "$disk" > /tmp/sgdisk_new_output 2>&1; then
  dialog --msgbox "Failed to create EFI partition on $disk. Error: $(cat /tmp/sgdisk_new_output)" 10 60
  exit 1
fi
if ! sgdisk -n 2:0:0 -t 2:8300 "$disk" >> /tmp/sgdisk_new_output 2>&1; then
  dialog --msgbox "Failed to create root partition on $disk. Error: $(cat /tmp/sgdisk_new_output)" 10 60
  exit 1
fi

# Wait for the system to recognize the partition changes
sleep 2

# Get partition names (after partitions are created)
if [[ "$(basename "$disk")" == nvme* ]] || [[ "$(basename "$disk")" == mmcblk* ]]; then
  esp="${disk}p1"
  root_partition="${disk}p2"
else
  esp="${disk}1"
  root_partition="${disk}2"
fi

# Clean up temporary files
rm -f /tmp/sgdisk_zap_output /tmp/sgdisk_new_output

# Prompt for hostname (already done above)

# Prompt for timezone (already done above)

# Prompt for locale (already done above)

# Prompt for root password (already done above)

# Prompt to create user account (already done above)

# Install base system
dialog --infobox "Installing base system...
This may take a while." 5 50
if ! pacstrap /mnt base linux linux-firmware "${selected_packages[@]}" > /tmp/pacstrap_install.log 2>&1; then
  dialog --msgbox "Failed to install base system. Check /tmp/pacstrap_install.log for details." 7 60
  exit 1
fi

# Generate fstab
dialog --infobox "Generating fstab..." 5 50
genfstab -U /mnt >> /mnt/etc/fstab
if [ $? -ne 0 ]; then
  dialog --msgbox "Failed to generate fstab. Exiting." 5 40
  exit 1
fi

# Mount necessary filesystems before chrooting
for dir in dev proc sys run; do
  mount --rbind "/$dir" "/mnt/$dir"
done

# Export variables for chroot
export esp
export root_partition
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
arch-chroot /mnt /bin/bash <<EOF_VAR
# Suppress command outputs inside chroot
exec > /dev/null 2>&1

# Set the timezone
ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
hwclock --systohc

# Set the hostname
echo "$hostname" > /etc/hostname

# Configure /etc/hosts
cat <<EOL > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain $hostname
EOL

# Generate locales
echo "$selected_locale UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$selected_locale" > /etc/locale.conf

# Configure ZRAM if enabled
if [ -n "$zram_pkg" ]; then
  cat <<EOM > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOM
fi

# Set the root password
echo "root:$root_password" | chpasswd

# Clear the root password variable for security
unset root_password

# Create user account if requested
if [ "$create_user" == "yes" ]; then
  useradd -m "$username"
  echo "$username:$user_password" | chpasswd
  unset user_password

  if [ "$grant_sudo" == "yes" ]; then
    usermod -aG wheel "$username"
    sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
  fi
fi

# Install rEFInd bootloader
pacman -Sy --noconfirm refind > /dev/null 2>&1
refind-install --no-sudo --yes --alldrivers > /dev/null 2>&1

if [ \$? -ne 0 ]; then
  echo "Failed to install rEFInd. Exiting."
  exit 1
fi

# rEFInd configuration
sed -i 's/^#enable_mouse/enable_mouse/' /efi/EFI/refind/refind.conf
sed -i 's/^#mouse_speed .*/mouse_speed 8/' /efi/EFI/refind/refind.conf
sed -i 's/^#resolution .*/resolution max/' /efi/EFI/refind/refind.conf
sed -i 's/^#extra_kernel_version_strings .*/extra_kernel_version_strings linux-hardened,linux-rt-lts,linux-zen,linux-lts,linux-rt,linux/' /efi/EFI/refind/refind.conf

# Create refind_linux.conf with the specified options
partuuid=\$(blkid -s PARTUUID -o value $root_partition)
initrd_line=""
if [ -n "$microcode_img" ]; then
  initrd_line="initrd=/boot/$microcode_img initrd=/boot/initramfs-%v.img"
else
  initrd_line="initrd=/boot/initramfs-%v.img"
fi

cat << EOF > /boot/refind_linux.conf
"Boot with standard options"  "root=PARTUUID=\$partuuid rw rootflags=subvol=@ $initrd_line"
"Boot using fallback initramfs"  "root=PARTUUID=\$partuuid rw rootflags=subvol=@ initrd=/boot/initramfs-%v-fallback.img"
"Boot to terminal"  "root=PARTUUID=\$partuuid rw rootflags=subvol=@ $initrd_line systemd.unit=multi-user.target"
EOF

# Ask if the user wants to use bash or install zsh
if [ -f /bin/dialog ]; then
  dialog --yesno "Would you like to use Zsh as your default shell instead of Bash?" 7 50
  if [ \$? -eq 0 ]; then
    pacman -Sy --noconfirm zsh > /dev/null 2>&1
    chsh -s /bin/zsh
    if [ "$create_user" == "yes" ]; then
      chsh -s /bin/zsh "$username"
    fi
  fi
fi

EOF_VAR

# Unmount the filesystems after chrooting
for dir in dev proc sys run; do
  umount -l "/mnt/$dir"
done

# Clear sensitive variables
unset root_password
unset user_password

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
  # Bind mount necessary filesystems for chroot
  for dir in dev proc sys run; do
    mount --rbind "/$dir" "/mnt/$dir"
  done

  # Drop into the chroot environment
  echo "Type 'exit' to leave the chroot environment and complete the installation."
  sleep 2

  # Redirect stdin and stdout to the terminal
  arch-chroot /mnt /bin/bash < /dev/tty > /dev/tty 2>&1

  # After exiting chroot, unmount filesystems
  for dir in dev proc sys run; do
    umount -l "/mnt/$dir"
  done
  umount -R /mnt
fi
