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

# Function to clear the screen and reset dialog
function reset_screen() {
  clear
  stty sane
}

# Set dialog options
DIALOG_OPTS="--colors --clear --ok-label OK --cancel-label Cancel"

# Check for UEFI mode
if [ ! -d /sys/firmware/efi/efivars ]; then
  dialog $DIALOG_OPTS --msgbox "Your system is not booted in UEFI mode.\nPlease reboot in UEFI mode to use this installer." 10 50
  reset_screen
  exit 1
fi

# Check internet connection
if ! ping -c 1 archlinux.org &> /dev/null; then
  dialog $DIALOG_OPTS --msgbox "Internet connection is required.\nPlease connect to the internet and rerun the installer." 10 50
  reset_screen
  exit 1
fi

# Set time synchronization
timedatectl set-ntp true

# Welcome message with extended information
dialog $DIALOG_OPTS --title "Arch Linux Minimal Installer" --msgbox "Welcome to the Arch Linux Minimal Installer.\n\nThis installer provides a quick and easy minimal install for Arch Linux, setting up a base system that boots to a terminal." 15 60

# Disk selection
disk=$(dialog $DIALOG_OPTS --stdout --title "Select Disk" --menu "Select the disk to install Arch Linux on:" 15 60 4 \
  $(lsblk -dn -o NAME,SIZE | awk '{print "/dev/" $1 " " $2}'))

if [ -z "$disk" ]; then
  dialog $DIALOG_OPTS --msgbox "No disk selected. Exiting." 10 40
  reset_screen
  exit 1
fi

# Confirm disk selection
dialog $DIALOG_OPTS --yesno "You have selected $disk. All data on this disk will be erased. Continue?" 10 50
if [ $? -ne 0 ]; then
  reset_screen
  exit 1
fi

# Wipe the disk and create partitions
sgdisk --zap-all "$disk"
sgdisk -n 1:0:+550M -t 1:ef00 "$disk"
sgdisk -n 2:0:0 -t 2:8300 "$disk"

# Get partition names
if [[ "$disk" == *"nvme"* ]]; then
  esp="${disk}p1"
  root_partition="${disk}p2"
else
  esp="${disk}1"
  root_partition="${disk}2"
fi

# Format partitions
dialog $DIALOG_OPTS --infobox "Formatting partitions..." 10 50
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
mount -o noatime,compress=zstd,discard=async,subvol=@ "$root_partition" /mnt
mkdir -p /mnt/{boot/efi,home,var/cache/pacman/pkg,var/log,.snapshots}
mount -o noatime,compress=zstd,discard=async,subvol=@home "$root_partition" /mnt/home
mount -o noatime,compress=zstd,discard=async,subvol=@pkg "$root_partition" /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,discard=async,subvol=@log "$root_partition" /mnt/var/log
mount -o noatime,compress=zstd,discard=async,subvol=@snapshots "$root_partition" /mnt/.snapshots

# Mount EFI partition
mount "$esp" /mnt/boot/efi

# Detect CPU and offer to install microcode
cpu_vendor=$(grep -m1 -E 'vendor_id|Vendor ID' /proc/cpuinfo | awk '{print $3}' | tr '[:upper:]' '[:lower:]')
microcode_pkg=""
microcode_img=""

if [[ "$cpu_vendor" == *"intel"* ]]; then
  dialog $DIALOG_OPTS --yesno "CPU detected: Intel\nWould you like to install intel-ucode?" 10 50
  if [ $? -eq 0 ]; then
    microcode_pkg="intel-ucode"
    microcode_img="intel-ucode.img"
  fi
elif [[ "$cpu_vendor" == *"amd"* ]]; then
  dialog $DIALOG_OPTS --yesno "CPU detected: AMD\nWould you like to install amd-ucode?" 10 50
  if [ $? -eq 0 ]; then
    microcode_pkg="amd-ucode"
    microcode_img="amd-ucode.img"
  fi
else
  dialog $DIALOG_OPTS --msgbox "CPU vendor not detected. Microcode will not be installed." 10 50
fi

# Prompt for hostname
hostname=$(dialog $DIALOG_OPTS --stdout --inputbox "Enter a hostname for your system:" 10 50)
if [ -z "$hostname" ]; then
  dialog $DIALOG_OPTS --msgbox "No hostname entered. Using default 'archlinux'." 10 50
  hostname="archlinux"
fi

# Prompt for timezone
timezones=($(timedatectl list-timezones))
timezone=$(dialog $DIALOG_OPTS --stdout --menu "Select your timezone:" 22 76 16 $(for i in "${!timezones[@]}"; do echo $i "${timezones[$i]}"; done))
if [ -z "$timezone" ]; then
  dialog $DIALOG_OPTS --msgbox "No timezone selected. Using 'UTC' as default." 10 50
  timezone="UTC"
else
  timezone="${timezones[$timezone]}"
fi

# Offer to install btrfs-progs
dialog $DIALOG_OPTS --yesno "Would you like to install btrfs-progs for Btrfs management?" 10 50
if [ $? -eq 0 ]; then
  btrfs_pkg="btrfs-progs"
else
  btrfs_pkg=""
fi

# Offer to enable ZRAM
dialog $DIALOG_OPTS --yesno "Would you like to enable ZRAM for swap?" 10 50
if [ $? -eq 0 ]; then
  zram_pkg="zram-generator"
else
  zram_pkg=""
fi

# Install base system with essential packages
dialog $DIALOG_OPTS --infobox "Installing base system..." 10 50
pacstrap /mnt base linux linux-firmware $microcode_pkg $btrfs_pkg $zram_pkg efibootmgr >> /tmp/installer.log 2>&1

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
  root_password=$(dialog $DIALOG_OPTS --no-cancel --passwordbox "Enter root password:" 10 50 3>&1 1>&2 2>&3 3>&-)
  root_password_confirm=$(dialog $DIALOG_OPTS --no-cancel --passwordbox "Confirm root password:" 10 50 3>&1 1>&2 2>&3 3>&-)
  if [ "$root_password" = "$root_password_confirm" ]; then
    break
  else
    dialog $DIALOG_OPTS --msgbox "Passwords do not match. Please try again." 10 50
  fi
done

# Set the root password in the chroot environment
echo "root:$root_password" | arch-chroot /mnt chpasswd

# Offer to install NetworkManager
dialog $DIALOG_OPTS --yesno "Would you like to install NetworkManager for network management?" 10 50
if [ $? -eq 0 ]; then
  arch-chroot /mnt pacman -Sy --noconfirm networkmanager
  arch-chroot /mnt systemctl enable NetworkManager
fi

# Install rEFInd bootloader with Btrfs support and tweaks
dialog $DIALOG_OPTS --infobox "Installing rEFInd bootloader..." 10 50
arch-chroot /mnt pacman -Sy --noconfirm refind efibootmgr dosfstools
arch-chroot /mnt refind-install

# rEFInd configuration
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

# Ask if the user wants to use bash or install zsh (moved after bootloader setup)
dialog $DIALOG_OPTS --yesno "Would you like to use Zsh as your default shell instead of Bash?" 10 50
if [ $? -eq 0 ]; then
  arch-chroot /mnt pacman -Sy --noconfirm zsh
  arch-chroot /mnt chsh -s /bin/zsh root
fi

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
dialog $DIALOG_OPTS --yesno "Installation complete! Would you like to reboot now or drop to the terminal for additional configuration?\n\nSelect 'No' to drop to the terminal." 15 60
if [ $? -eq 0 ]; then
  umount -R /mnt
  reboot
else
  reset_screen
fi
