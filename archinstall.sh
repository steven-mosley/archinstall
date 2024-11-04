#!/bin/bash

# Arch Linux Minimal Installation Script with Btrfs, rEFInd, and ZRAM
# WARNING: This script will erase the selected disk.

# Enable logging for debugging purposes
exec > >(tee -i /tmp/installer.log)
exec 2>&1

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# Install dialog if not already installed
if ! command -v dialog &> /dev/null; then
  pacman -Sy --noconfirm dialog
fi

# Clear the screen
clear

# Check for UEFI mode
if [ ! -d /sys/firmware/efi/efivars ]; then
  dialog --msgbox "Your system is not booted in UEFI mode.\nPlease reboot in UEFI mode to use this installer." 0 0
  clear
  exit 1
fi

# Check internet connection
if ! ping -c 1 archlinux.org &> /dev/null; then
  dialog --msgbox "Internet connection is required.\nPlease connect to the internet and rerun the installer." 0 0
  clear
  exit 1
fi

# Set time synchronization
timedatectl set-ntp true

# Welcome message with extended information
dialog --title "Arch Linux Minimal Installer" --msgbox "Welcome to the Arch Linux Minimal Installer.\n\nThis installer provides a quick and easy minimal install for Arch Linux, quickly setting up a base system that boots to a terminal." 0 0

# Disk selection
disk=$(dialog --stdout --title "Select Disk" --menu "Select the disk to install Arch Linux on:" 0 0 0 \
  $(lsblk -dn -o NAME,SIZE | awk '{print "/dev/" $1 " " $2}'))

if [ -z "$disk" ]; then
  dialog --msgbox "No disk selected. Exiting." 0 0
  clear
  exit 1
fi

# Detect existing Windows partitions
disk_partitions=$(lsblk -o NAME,FSTYPE,LABEL,UUID,MOUNTPOINTS "$disk" | grep -E 'ntfs|FAT32')
free_space=$(lsblk -b -o NAME,TYPE,FREE "$disk" | grep "$(basename "$disk")" | awk '{print $3}')
min_required_space=$((30 * 1024 * 1024 * 1024)) # Minimum required space is 30GB

if [ -n "$disk_partitions" ]; then
  if [ "$free_space" -ge "$min_required_space" ]; then
    dialog --yesno "Sufficient unallocated space detected on $disk. Would you like to proceed with using this disk for installation?" 0 0
    if [ $? -ne 0 ]; then
      dialog --msgbox "You can select another disk for installation." 0 0
      # Code to select another disk
      disk=$(dialog --stdout --title "Select Disk" --menu "Select the disk to install Arch Linux on:" 0 0 0 \
        $(lsblk -dn -o NAME,SIZE | awk '{print "/dev/" $1 " " $2}'))
      if [ -z "$disk" ]; then
        dialog --msgbox "No disk selected. Exiting." 0 0
        clear
        exit 1
      fi
    else
      # Proceed with installation
      # Wipe the disk
      sgdisk --zap-all "$disk"
      # Create partitions
      sgdisk -n 1:0:+550M -t 1:ef00 "$disk"
      sgdisk -n 2:0:0 -t 2:8300 "$disk"
    fi
  else
    dialog --msgbox "Windows partitions detected on $disk. You can choose to install Arch Linux alongside Windows." 0 0
    # Ask user if they want to proceed with dual boot
    dialog --yesno "Would you like to install Arch Linux alongside Windows by shrinking an existing partition?" 0 0
    if [ $? -ne 0 ]; then
      dialog --msgbox "You can select another disk for installation." 0 0
      # Code to select another disk
      disk=$(dialog --stdout --title "Select Disk" --menu "Select the disk to install Arch Linux on:" 0 0 0 \
        $(lsblk -dn -o NAME,SIZE | awk '{print "/dev/" $1 " " $2}'))
      if [ -z "$disk" ]; then
        dialog --msgbox "No disk selected. Exiting." 0 0
        clear
        exit 1
      fi
    else
      # Prompt user to select the Windows partition
      windows_partition=$(dialog --stdout --title "Select Windows Partition" --menu \
        "Select the main Windows partition to resize:" 0 0 0 \
        $(lsblk -rn -o NAME,SIZE,FSTYPE "$disk" | grep ntfs | awk '{print $1 " " $2}'))
      if [ -z "$windows_partition" ]; then
        dialog --msgbox "No Windows partition selected. Exiting." 0 0
        clear
        exit 1
      fi
      windows_partition="${disk}${windows_partition}"
      # Ask user how much space to allocate for Arch Linux
      arch_space=$(dialog --stdout --inputbox "Enter the amount of space (in GB) you want to allocate for Arch Linux:" 0 0)
      if [ -z "$arch_space" ]; then
        dialog --msgbox "No space entered. Exiting." 0 0
        clear
        exit 1
      fi
      # Shrink Windows partition
      dialog --infobox "Shrinking Windows partition to create space for Arch Linux..." 0 0
      parted "$disk" resizepart "${windows_partition##*p}" "-${arch_space}G"
      # Create partitions
      sgdisk -n 1:0:+550M -t 1:ef00 "$disk"
      sgdisk -n 2:0:0 -t 2:8300 "$disk"
    fi
  fi
else
  dialog --yesno "No Windows partitions detected. Are you sure you want to erase all data on $disk?" 0 0
  if [ $? -ne 0 ]; then
    dialog --msgbox "You can select another disk for installation." 0 0
    # Code to select another disk
    disk=$(dialog --stdout --title "Select Disk" --menu "Select the disk to install Arch Linux on:" 0 0 0 \
      $(lsblk -dn -o NAME,SIZE | awk '{print "/dev/" $1 " " $2}'))
    if [ -z "$disk" ]; then
      dialog --msgbox "No disk selected. Exiting." 0 0
      clear
      exit 1
    fi
  else
    # Wipe the disk
    sgdisk --zap-all "$disk"
    # Create partitions
    sgdisk -n 1:0:+550M -t 1:ef00 "$disk"
    sgdisk -n 2:0:0 -t 2:8300 "$disk"
  fi
fi

# Get partition names
if [[ "$disk" == *"nvme"* ]]; then
  esp="${disk}p1"
  root_partition="${disk}p2"
else
  esp="${disk}1"
  root_partition="${disk}2"
fi

# Format partitions
dialog --infobox "Formatting partitions..." 0 0
mkfs.vfat -F32 "$esp"
mkfs.btrfs -f -L Arch "$root_partition"

# Mount root partition
mount "$root_partition" /mnt

# Create Btrfs subvolumes
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@pkg
btrfs su cr /mnt/@log
btrfs su cr /mnt/@snapshots

# Unmount root partition
umount /mnt

# Mount subvolumes with options
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@ "$root_partition" /mnt
mkdir -p /mnt/{boot/efi,home,var/cache/pacman/pkg,var/log,.snapshots}
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@home "$root_partition" /mnt/home
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@pkg "$root_partition" /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@log "$root_partition" /mnt/var/log
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@snapshots "$root_partition" /mnt/.snapshots

# Mount EFI partition
mount "$esp" /mnt/boot/efi

# Detect CPU and offer to install microcode
cpu_vendor=$(grep -m1 -E 'vendor_id|Vendor ID' /proc/cpuinfo | awk '{print $3}' | tr '[:upper:]' '[:lower:]')
microcode_pkg=""
microcode_img=""

if [[ "$cpu_vendor" == *"intel"* ]]; then
  dialog --yesno "CPU detected: Intel\nWould you like to install intel-ucode?" 0 0
  if [ $? -eq 0 ]; then
    microcode_pkg="intel-ucode"
    microcode_img="intel-ucode.img"
  fi
elif [[ "$cpu_vendor" == *"amd"* ]]; then
  dialog --yesno "CPU detected: AMD\nWould you like to install amd-ucode?" 0 0
  if [ $? -eq 0 ]; then
    microcode_pkg="amd-ucode"
    microcode_img="amd-ucode.img"
  fi
else
  dialog --msgbox "CPU vendor not detected. Microcode will not be installed." 0 0
fi

# Prompt for hostname
hostname=$(dialog --stdout --inputbox "Enter a hostname for your system:" 0 0)
if [ -z "$hostname" ]; then
  dialog --msgbox "No hostname entered. Using default 'archlinux'." 0 0
  hostname="archlinux"
fi

# Prompt for timezone
timezones=($(timedatectl list-timezones))
timezone_selection=$(dialog --stdout --menu "Select your timezone:" 0 0 0 "${!timezones[@]}" "${timezones[@]}")
if [ -z "$timezone_selection" ]; then
  dialog --msgbox "No timezone selected. Using 'UTC' as default." 0 0
  timezone="UTC"
else
  timezone="${timezones[$timezone_selection]}"
fi

# Offer to install btrfs-progs
dialog --yesno "Would you like to install btrfs-progs for Btrfs management?" 0 0
if [ $? -eq 0 ]; then
  btrfs_pkg="btrfs-progs"
else
  btrfs_pkg=""
fi

# Offer to enable ZRAM
dialog --yesno "Would you like to enable ZRAM for swap?" 0 0
if [ $? -eq 0 ]; then
  zram_pkg="zram-generator"
else
  zram_pkg=""
fi

# Install base system with essential packages
dialog --infobox "Installing base system..." 0 0
if ! pacstrap /mnt base linux linux-firmware shadow $microcode_pkg $btrfs_pkg $zram_pkg efibootmgr; then
  dialog --msgbox "Failed to install base system. Check /tmp/installer.log for details." 0 0
  exit 1
fi

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Export variables for chroot
export hostname
export timezone
export zram_pkg

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF
# Set the timezone
ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime
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
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Configure ZRAM if enabled
if [ -n "$zram_pkg" ]; then
  cat <<EOM > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOM
fi
EOF

# Set root password
while true; do
  root_password=$(dialog --no-cancel --passwordbox "Enter root password:" 0 0 3>&1 1>&2 2>&3 3>&-)
  root_password_confirm=$(dialog --no-cancel --passwordbox "Confirm root password:" 0 0 3>&1 1>&2 2>&3 3>&-)
  if [ "$root_password" = "$root_password_confirm" ]; then
    break
  else
    dialog --msgbox "Passwords do not match. Please try again." 0 0
  fi
done

# Set the root password in the chroot environment
echo "root:$root_password" | arch-chroot /mnt chpasswd

# Offer to install NetworkManager
dialog --yesno "Would you like to install NetworkManager for network management?" 0 0
if [ $? -eq 0 ]; then
  arch-chroot /mnt pacman -Sy --noconfirm networkmanager
  arch-chroot /mnt systemctl enable NetworkManager
fi

# Ask if the user wants to use bash or install zsh
dialog --yesno "Would you like to use Zsh as your default shell instead of Bash?" 0 0
if [ $? -eq 0 ]; then
  arch-chroot /mnt pacman -Sy --noconfirm zsh
  arch-chroot /mnt chsh -s /bin/zsh root
fi

# Install rEFInd bootloader with Btrfs support and tweaks
dialog --infobox "Installing rEFInd bootloader..." 0 0
arch-chroot /mnt pacman -Sy --noconfirm refind efibootmgr

# Verify that refind-install is available
if ! arch-chroot /mnt which refind-install &> /dev/null; then
  dialog --msgbox "refind-install not found in chroot environment. Installation cannot proceed." 0 0
  exit 1
fi

# Proceed with rEFInd installation
arch-chroot /mnt refind-install

# rEFInd configuration
# Modify refind.conf
arch-chroot /mnt sed -i 's/^#enable_mouse/enable_mouse/' /boot/efi/EFI/refind/refind.conf
arch-chroot /mnt sed -i 's/^#mouse_speed .*/mouse_speed 8/' /boot/efi/EFI/refind/refind.conf
arch-chroot /mnt sed -i 's/^#resolution .*/resolution max/' /boot/efi/EFI/refind/refind.conf
arch-chroot /mnt sed -i 's/^#extra_kernel_version_strings .*/extra_kernel_version_strings linux-hardened,linux-rt-lts,linux-zen,linux-lts,linux-rt,linux/' /boot/efi/EFI/refind/refind.conf

# Create refind_linux.conf with the specified options
partuuid=$(blkid -s PARTUUID -o value "$root_partition")
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

# Create first_login.sh script for initial login instructions
cat << 'EOM' > /mnt/root/first_login.sh
#!/bin/bash

clear
cat << 'EOF'
Welcome to your new Arch Linux system!

To create a new user and grant sudo privileges, follow these steps:

1. Create a new user (replace 'username' with your desired username):
   useradd -m username

2. Set the password for the new user:
   passwd username

3. Install sudo (if not already installed):
   pacman -Sy sudo

4. Add the user to the wheel group:
   usermod -aG wheel username

5. Edit the sudoers file to grant sudo privileges:
   EDITOR=nano visudo

   Uncomment the line:
   %wheel ALL=(ALL) ALL

6. Install a text editor (e.g., nano, vim, or emacs) if needed:
   pacman -Sy nano

You're all set!
EOF

# Remove the script and its call from .bash_profile
rm -- "$0"
sed -i '/first_login.sh/d' ~/.bash_profile
EOM

# Make the script executable
chmod +x /mnt/root/first_login.sh

# Add the script to root's .bash_profile
echo "if [ -f ~/first_login.sh ]; then ~/first_login.sh; fi" >> /mnt/root/.bash_profile

# Finish
dialog --yesno "Installation complete! Would you like to reboot now or drop to the terminal for additional configuration?\n\nSelect 'No' to drop to the terminal." 0 0
if [ $? -eq 0 ]; then
  # Reboot the system
  umount -R /mnt
  reboot
else
  # Drop to the terminal
  clear
fi
