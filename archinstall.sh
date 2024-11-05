#!/bin/bash

# Arch Linux Minimal Installation Script with Btrfs, rEFInd, and ZRAM
# WARNING: This script will erase the selected disk or shrink an existing Windows partition.

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

# Welcome message with extended information
dialog --title "Arch Linux Minimal Installer" --msgbox "Welcome to the Arch Linux Minimal Installer.\n\nThis installer provides a quick and easy minimal install for Arch Linux, setting up a base system that boots to a terminal.\n\nThis is version 2.0." 12 70

# Disk selection
echo "[DEBUG] Prompting for disk selection"
disk=$(dialog --stdout --title "Select Disk" --menu "Select the disk to install Arch Linux on:" 15 60 4 $(lsblk -dn -o NAME,SIZE | awk '{print "/dev/" $1 " " $2}'))
if [ -z "$disk" ]; then
  dialog --msgbox "No disk selected. Exiting." 5 40
  clear
  exit 1
fi

# Detect existing Windows partitions or other partitions
existing_partitions=$(lsblk -o NAME,TYPE $disk | grep part)
if [ -n "$existing_partitions" ]; then
  dialog --yesno "Existing partitions detected on $disk. Would you like to destroy the current partitions and recreate them?" 7 60
  if [ $? -eq 0 ]; then
    echo "[DEBUG] Destroying existing partitions on $disk"
    sgdisk --zap-all $disk
  else
    dialog --msgbox "Installation canceled. Exiting." 5 40
    clear
    exit 1
  fi
fi

# Create partitions
echo "[DEBUG] Creating partitions on $disk"
# Partition 1: EFI System Partition
sgdisk -n 1:0:+550M -t 1:ef00 $disk
# Partition 2: Root partition
sgdisk -n 2:0:0 -t 2:8300 $disk

# Get partition names
echo "[DEBUG] Determining partition names"
if [[ "$disk" == *"nvme"* ]]; then
  esp="${disk}p1"
  root_partition="${disk}p2"
else
  esp="${disk}1"
  root_partition="${disk}2"
fi

# Format partitions
echo "[DEBUG] Formatting partitions"
dialog --infobox "Formatting partitions..." 5 40
mkfs.vfat -F32 $esp
mkfs.btrfs -f -L Arch $root_partition

# Mount root partition
echo "[DEBUG] Mounting root partition $root_partition"
mount $root_partition /mnt

# Create Btrfs subvolumes
echo "[DEBUG] Creating Btrfs subvolumes"
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@pkg
btrfs su cr /mnt/@log
btrfs su cr /mnt/@snapshots

# Unmount root partition
echo "[DEBUG] Unmounting root partition"
umount /mnt

# Mount subvolumes with options
echo "[DEBUG] Mounting Btrfs subvolumes"
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@ $root_partition /mnt
mkdir -p /mnt/{boot/efi,home,var/cache/pacman/pkg,var/log,.snapshots}
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@home $root_partition /mnt/home
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@pkg $root_partition /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@log $root_partition /mnt/var/log
mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@snapshots $root_partition /mnt/.snapshots

# Mount EFI partition
echo "[DEBUG] Mounting EFI partition $esp"
if ! mount | grep -q '/mnt/boot/efi'; then
  mkdir -p /mnt/boot/efi
  mount $esp /mnt/boot/efi
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

# Prompt for hostname
echo "[DEBUG] Prompting for hostname"
hostname=$(dialog --stdout --inputbox "Enter a hostname for your system:" 8 40)
if [ -z "$hostname" ]; then
  dialog --msgbox "No hostname entered. Using default 'archlinux'." 6 50
  hostname="archlinux"
fi

# Prompt for timezone
echo "[DEBUG] Prompting for timezone"
available_timezones=$(find /usr/share/zoneinfo/ -type f | sed 's#/usr/share/zoneinfo/##')
timezone=$(dialog --stdout --title "Select Timezone" --menu "Select your timezone:" 20 60 15 $(echo "$available_timezones" | nl -w2 -s" "))
if [ -z "$timezone" ]; then
  dialog --msgbox "No timezone selected. Using 'UTC' as default." 6 50
  timezone="UTC"
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

# Install base system
echo "[DEBUG] Installing base system"
dialog --infobox "Installing base system..." 5 40
pacstrap /mnt base linux linux-firmware $microcode_pkg "$btrfs_pkg" "$zram_pkg" "$networkmanager_pkg"

# Generate fstab
echo "[DEBUG] Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
echo "[DEBUG] Entering chroot to configure the new system"
arch-chroot /mnt /bin/bash <<EOF
# Set the timezone
echo "[DEBUG] Setting timezone to $timezone"
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
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
echo "[DEBUG] Prompting for locale selection"
available_locales=$(awk '/^[a-z]/ {print $1}' /usr/share/i18n/SUPPORTED)
selected_locale=$(dialog --stdout --title "Select Locale" --menu "Select your locale:" 20 60 15 $(echo "$available_locales" | nl -w2 -s" "))
if [ -z "$selected_locale" ]; then
  dialog --msgbox "No locale selected. Using 'en_US.UTF-8' as default." 6 50
  selected_locale="en_US.UTF-8"
fi
echo "$selected_locale UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$selected_locale" > /etc/locale.conf

# Configure ZRAM if enabled
echo "[DEBUG] Configuring ZRAM if enabled"
if [ -n "$zram_pkg" ]; then
  cat <<EOM > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOM
fi

EOF

# Set root password
echo "[DEBUG] Prompting for root password"
root_password=$(dialog --stdout --insecure --passwordbox "Enter root password:" 8 40)
if [ -z "$root_password" ]; then
  dialog --msgbox "No password entered. Exiting." 5 40
  clear
  exit 1
fi
arch-chroot /mnt /bin/bash -c "echo -e '$root_password\n$root_password' | passwd"

# Ask if the user wants to use bash or install zsh
echo "[DEBUG] Prompting for shell selection"
dialog --yesno "Would you like to use Zsh as your default shell instead of Bash?" 7 50
if [ $? -eq 0 ]; then
  arch-chroot /mnt pacman -Sy --noconfirm zsh
  arch-chroot /mnt chsh -s /bin/zsh
fi

# Install rEFInd bootloader with Btrfs support and tweaks
echo "[DEBUG] Installing rEFInd bootloader"
dialog --infobox "Installing rEFInd bootloader..." 5 40
arch-chroot /mnt pacman -Sy --noconfirm refind
arch-chroot /mnt refind-install

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
  initrd_line="initrd=@\\boot\\$microcode_img initrd=@\\boot\\initramfs-%v.img"
else
  initrd_line="initrd=@\\boot\\initramfs-%v.img"
fi

cat << EOF > /mnt/boot/refind_linux.conf
"Boot with standard options"  "root=PARTUUID=$partuuid rw rootflags=subvol=@ $initrd_line"
"Boot using fallback initramfs"  "root=PARTUUID=$partuuid rw rootflags=subvol=@ initrd=@\\boot\\initramfs-%v-fallback.img"
"Boot to terminal"  "root=PARTUUID=$partuuid rw rootflags=subvol=@ initrd=@\\boot\\initramfs-%v.img systemd.unit=multi-user.target"
EOF

# Copy refind_linux.conf to rEFInd directory
echo "[DEBUG] Copying refind_linux.conf to rEFInd directory"
cp /mnt/boot/refind_linux.conf /mnt/boot/efi/EFI/refind/

# Create first_login.sh script for initial login instructions
echo "[DEBUG] Creating first_login.sh script"
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

# Finish installation
dialog --yesno "Installation complete! Would you like to reboot now or drop to the terminal for additional configuration?\n\nSelect 'No' to drop to the terminal." 10 70
if [ $? -eq 0 ]; then
  # Reboot the system
  umount -R /mnt
  reboot
else
  # Drop to the terminal
  arch-chroot /mnt
  clear
fi
