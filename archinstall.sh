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

# Function to display dialogs with consistent settings
function show_dialog() {
  dialog --clear --colors --backtitle "Arch Linux Installation" "$@"
}

# Check for UEFI mode
if [ ! -d /sys/firmware/efi/efivars ]; then
  show_dialog --msgbox "\nYour system is not booted in UEFI mode.\nPlease reboot in UEFI mode to use this installer." 10 60
  reset_screen
  exit 1
fi

# Check internet connection
if ! ping -c 1 archlinux.org &> /dev/null; then
  show_dialog --msgbox "\nInternet connection is required.\nPlease connect to the internet and rerun the installer." 10 60
  reset_screen
  exit 1
fi

# Set time synchronization
timedatectl set-ntp true

# Welcome message with extended information
show_dialog --title "Arch Linux Minimal Installer" --msgbox "\nWelcome to the Arch Linux Minimal Installer.\n\nThis installer provides a quick and easy minimal install for Arch Linux, setting up a base system that boots to a terminal." 15 60

# Disk selection
disk_options=($(lsblk -dn -o NAME,SIZE | awk '{print "/dev/" $1 " " $2}'))
disk=$(show_dialog --stdout --title "Select Disk" --menu "Select the disk to install Arch Linux on:" 15 60 4 "${disk_options[@]}")

if [ -z "$disk" ]; then
  show_dialog --msgbox "\nNo disk selected. Exiting." 10 40
  reset_screen
  exit 1
fi

# Confirm disk selection
show_dialog --yes-label "Continue" --no-label "Cancel" --yesno "\nYou have selected $disk.\nAll data on this disk will be erased.\n\nContinue?" 12 60
if [ $? -ne 0 ]; then
  show_dialog --msgbox "\nInstallation canceled by user. Exiting." 10 40
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
show_dialog --infobox "\nFormatting partitions..." 5 60
mkfs.vfat -F32 "$esp" >/dev/null 2>&1
mkfs.btrfs -f -L Arch "$root_partition" >/dev/null 2>&1

# Mount root partition
mount "$root_partition" /mnt

# Create Btrfs subvolumes
btrfs su cr /mnt/@ >/dev/null 2>&1
btrfs su cr /mnt/@home >/dev/null 2>&1
btrfs su cr /mnt/@pkg >/dev/null 2>&1
btrfs su cr /mnt/@log >/dev/null 2>&1
btrfs su cr /mnt/@snapshots >/dev/null 2>&1

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
cpu_vendor=$(lscpu | grep -i 'vendor id:' | awk '{print $3}' | tr '[:upper:]' '[:lower:]')
microcode_pkg=""
microcode_img=""

if [[ "$cpu_vendor" == *"intel"* ]]; then
  show_dialog --yesno "\nCPU detected: Intel\n\nWould you like to install intel-ucode?" 10 60
  if [ $? -eq 0 ]; then
    microcode_pkg="intel-ucode"
    microcode_img="intel-ucode.img"
  fi
elif [[ "$cpu_vendor" == *"amd"* ]]; then
  show_dialog --yesno "\nCPU detected: AMD\n\nWould you like to install amd-ucode?" 10 60
  if [ $? -eq 0 ]; then
    microcode_pkg="amd-ucode"
    microcode_img="amd-ucode.img"
  fi
else
  show_dialog --msgbox "\nCPU vendor not detected. Microcode will not be installed." 10 60
fi

# Prompt for hostname
hostname=$(show_dialog --stdout --inputbox "\nEnter a hostname for your system:" 10 60)
if [ -z "$hostname" ]; then
  show_dialog --msgbox "\nNo hostname entered. Using default 'archlinux'." 10 60
  hostname="archlinux"
fi

# Prompt for timezone
timezones=($(timedatectl list-timezones))
timezone_selection=$(dialog --clear --stdout --title "Select Timezone" --menu "Select your timezone:" 20 70 15 "${timezones[@]}")
if [ -z "$timezone_selection" ]; then
  show_dialog --msgbox "\nNo timezone selected. Using 'UTC' as default." 10 60
  timezone="UTC"
else
  timezone="$timezone_selection"
fi

# Offer to install btrfs-progs
show_dialog --yesno "\nWould you like to install btrfs-progs for Btrfs management?" 10 60
if [ $? -eq 0 ]; then
  btrfs_pkg="btrfs-progs"
else
  btrfs_pkg=""
fi

# Offer to enable ZRAM
show_dialog --yesno "\nWould you like to enable ZRAM for swap?" 10 60
if [ $? -eq 0 ]; then
  zram_pkg="zram-generator"
else
  zram_pkg=""
fi

# Install base system with essential packages
show_dialog --infobox "\nInstalling base system...\nThis may take a while." 10 60
pacstrap /mnt base linux linux-firmware $microcode_pkg $btrfs_pkg $zram_pkg efibootmgr >/dev/null 2>&1

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system and configure it
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
  root_password=$(dialog --clear --stdout --passwordbox "\nEnter root password:" 10 60)
  root_password_confirm=$(dialog --clear --stdout --passwordbox "\nConfirm root password:" 10 60)
  if [ "$root_password" = "$root_password_confirm" ]; then
    break
  else
    show_dialog --msgbox "\nPasswords do not match. Please try again." 10 60
  fi
done

# Set the root password in the chroot environment
echo "root:$root_password" | arch-chroot /mnt chpasswd

# Offer to install NetworkManager
show_dialog --yesno "\nWould you like to install NetworkManager for network management?" 10 60
if [ $? -eq 0 ]; then
  arch-chroot /mnt pacman -Sy --noconfirm networkmanager >/dev/null 2>&1
  arch-chroot /mnt systemctl enable NetworkManager
fi

# Install rEFInd bootloader with Btrfs support and tweaks
show_dialog --infobox "\nInstalling rEFInd bootloader..." 10 60
arch-chroot /mnt pacman -Sy --noconfirm refind >/dev/null 2>&1

# Ensure refind-install is available
if ! arch-chroot /mnt which refind-install &> /dev/null; then
  show_dialog --msgbox "\nrefind-install not found in chroot environment. Installation cannot proceed." 10 60
  reset_screen
  exit 1
fi

# Proceed with rEFInd installation
arch-chroot /mnt refind-install >/dev/null 2>&1

# rEFInd configuration
arch-chroot /mnt sed -i 's/^#enable_mouse/enable_mouse/' /boot/efi/EFI/refind/refind.conf
arch-chroot /mnt sed -i 's/^#mouse_speed .*/mouse_speed 8/' /boot/efi/EFI/refind/refind.conf
arch-chroot /mnt sed -i 's/^#resolution .*/resolution max/' /boot/efi/EFI/refind/refind.conf
arch-chroot /mnt sed -i 's/^#extra_kernel_version_strings .*/extra_kernel_version_strings linux-hardened,linux-zen,linux-lts/' /boot/efi/EFI/refind/refind.conf

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
show_dialog --yesno "\nWould you like to use Zsh as your default shell instead of Bash?" 10 60
if [ $? -eq 0 ]; then
  arch-chroot /mnt pacman -Sy --noconfirm zsh >/dev/null 2>&1
  arch-chroot /mnt chsh -s /bin/zsh root >/dev/null 2>&1
  shell_config_file="/root/.zshrc"
else
  shell_config_file="/root/.bash_profile"
fi

# Create first_login.sh script for initial login instructions
arch-chroot /mnt bash -c "cat << 'EOM' > /root/first_login.sh
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

# Remove the script and its call from the shell configuration file
rm -- "\$0"
sed -i '/first_login.sh/d' ~/.'"$(basename "$shell_config_file")"'
EOM"

# Make the script executable
arch-chroot /mnt chmod +x /root/first_login.sh

# Add the script to the appropriate shell's configuration file
arch-chroot /mnt bash -c "echo 'if [ -f ~/first_login.sh ]; then ~/first_login.sh; fi' >> $shell_config_file"

# Finish
show_dialog --yes-label "Reboot" --no-label "Chroot" --yesno "\nInstallation complete!\n\nWould you like to reboot now or enter the chroot environment for additional configuration?\n\nSelect 'Chroot' to enter the chroot environment." 15 60
if [ $? -eq 0 ]; then
  umount -R /mnt
  reboot
else
  reset_screen
  arch-chroot /mnt
fi
