#!/bin/bash

# Install dialog if not present
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

# Check for internet connectivity
if ! ping -c 1 -W 1 archlinux.org &> /dev/null; then
    dialog --msgbox "No internet connectivity detected.\nPlease connect to the internet and rerun the installer.\n\nFor assistance, visit:\nhttps://wiki.archlinux.org/title/Installation_guide#Connect_to_the_internet" 12 60
    clear
    exit 1
fi

# Enable NTP synchronization
timedatectl set-ntp true

dialog --title "Arch Linux Automated Installer" --msgbox "Welcome to the Arch Linux Automated Installer." 10 60

# Disk Selection
disks_array=()
while read -r name size; do
    disks_array+=("/dev/$name" "$size" "OFF")
done < <(lsblk -d -e 7,11 -o NAME,SIZE -n)

DISK=$(dialog --stdout --title "Select Disk" --radiolist "Choose the disk to install Arch Linux:" 15 60 4 "${disks_array[@]}")

if [ -z "$DISK" ]; then
    dialog --msgbox "No disk selected. Installation cancelled." 7 50
    clear
    exit 1
fi

# Confirm with the user
dialog --yesno "All data on $DISK will be erased. Are you sure?" 7 50
if [ $? -ne 0 ]; then
    dialog --msgbox "Installation cancelled." 5 30
    clear
    exit 1
fi

# Recommend BTRFS partition layout
dialog --title "Partition Layout" --msgbox "Recommended BTRFS partition layout:\n\n- EFI System Partition (ESP): /boot\n- BTRFS subvolumes:\n  - @ mounted at /\n  - @home mounted at /home\n  - @pkg mounted at /var/cache/pacman/pkg\n  - @log mounted at /var/log\n  - @snapshots mounted at /.snapshots" 15 70

dialog --yesno "Do you want to use the recommended BTRFS layout?" 7 50
if [ $? -ne 0 ]; then
    dialog --msgbox "Custom partitioning is not implemented in this script.\nPlease partition your disk manually and rerun the script." 8 60
    clear
    exit 1
fi

# Partition the disk
dialog --infobox "Partitioning the disk..." 5 40

# Wipe the disk
sgdisk --zap-all $DISK

# Create a new GPT partition table
sgdisk --clear $DISK

# Create partitions
# 1. EFI System Partition
sgdisk -n 1:0:+550M -t 1:ef00 $DISK
# 2. Root partition
sgdisk -n 2:0:0 -t 2:8300 $DISK

# Get partition names
if [[ $DISK =~ nvme ]]; then
    ESP="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    ESP="${DISK}1"
    ROOT_PART="${DISK}2"
fi

# Format the partitions
dialog --infobox "Formatting the partitions..." 5 40

mkfs.vfat -F32 $ESP
mkfs.btrfs -f -L "Arch" $ROOT_PART

# Mount the root partition
mount $ROOT_PART /mnt

# Create BTRFS subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@snapshots

# Unmount the root partition
umount /mnt

# Mount subvolumes with recommended options
MOUNT_OPTIONS="noatime,compress=zstd,discard=async,space_cache=v2"

mount -o $MOUNT_OPTIONS,subvol=@ $ROOT_PART /mnt
mkdir -p /mnt/{boot,home,var/cache/pacman/pkg,var/log,.snapshots}
mount -o $MOUNT_OPTIONS,subvol=@home $ROOT_PART /mnt/home
mount -o $MOUNT_OPTIONS,subvol=@pkg $ROOT_PART /mnt/var/cache/pacman/pkg
mount -o $MOUNT_OPTIONS,subvol=@log $ROOT_PART /mnt/var/log
mount -o $MOUNT_OPTIONS,subvol=@snapshots $ROOT_PART /mnt/.snapshots

# Mount the EFI partition at /boot
mount $ESP /mnt/boot

# CPU Microcode
dialog --infobox "Detecting CPU type..." 5 40

CPU_VENDOR=$(lscpu | awk -F: '/Vendor ID/ {gsub(/^[ \t]+/, "", $2); print $2}')

if [[ "$CPU_VENDOR" == *"GenuineIntel"* ]]; then
    MICROCODE="intel-ucode"
    MICROCODE_IMG="intel-ucode.img"
elif [[ "$CPU_VENDOR" == *"AuthenticAMD"* ]]; then
    MICROCODE="amd-ucode"
    MICROCODE_IMG="amd-ucode.img"
else
    CPU_CHOICE=$(dialog --stdout --title "CPU Microcode" --menu "Unable to detect CPU microcode. Do you have an Intel or AMD CPU?" 10 50 2 \
    "intel" "Intel CPU" \
    "amd" "AMD CPU")

    if [ "$CPU_CHOICE" == "intel" ]; then
        MICROCODE="intel-ucode"
        MICROCODE_IMG="intel-ucode.img"
    elif [ "$CPU_CHOICE" == "amd" ]; then
        MICROCODE="amd-ucode"
        MICROCODE_IMG="amd-ucode.img"
    else
        dialog --msgbox "Invalid choice. Defaulting to no microcode." 5 50
        MICROCODE=""
        MICROCODE_IMG=""
    fi
fi

dialog --msgbox "Microcode selected: $MICROCODE" 5 50

# Ask if the user wants to perform a minimal install
dialog --yesno "Do you want to perform a minimal install?" 7 50
if [ $? -eq 0 ]; then
    MINIMAL_INSTALL="yes"
else
    MINIMAL_INSTALL="no"
fi

if [[ "$MINIMAL_INSTALL" == "no" ]]; then
    # Text editor choice
    EDITOR_CHOICE=$(dialog --stdout --title "Select Text Editor" --menu "Choose a text editor to install:" 10 50 3 \
    "vi" "vi editor" \
    "vim" "Vim editor" \
    "nano" "Nano editor")

    if [ -z "$EDITOR_CHOICE" ]; then
        dialog --msgbox "No editor selected. Installation cancelled." 7 50
        clear
        exit 1
    fi

    # NetworkManager installation
    dialog --yesno "Would you like to install NetworkManager to manage network connections?" 7 60
    if [ $? -eq 0 ]; then
        NETWORK_PACKAGES="networkmanager"
        ENABLE_NM="yes"
    else
        NETWORK_PACKAGES=""
        ENABLE_NM="no"
    fi

    # Ask for additional packages
    ADDITIONAL_PACKAGES=$(dialog --stdout --inputbox "Enter any additional packages to install during pacstrap (separated by spaces), or leave blank to skip:" 10 60)

    # Ask the user if they want to install a GUI
    GUI_CHOICE=$(dialog --stdout --title "GUI/Desktop Environment" --menu "Would you like to install a GUI/Desktop Environment?" 15 60 4 \
    "GNOME" "GNOME Desktop Environment" \
    "KDE Plasma" "KDE Plasma Desktop Environment" \
    "XFCE" "XFCE Desktop Environment" \
    "None" "No GUI/Desktop Environment")

    if [ -z "$GUI_CHOICE" ]; then
        dialog --msgbox "No GUI selected. Installation cancelled." 7 50
        clear
        exit 1
    fi

    if [[ "$GUI_CHOICE" != "None" ]]; then
        # Prompt for Wayland or X11
        DISPLAY_SERVER=$(dialog --stdout --title "Display Server" --menu "Do you want to use Wayland or X11?" 10 40 2 \
        "Wayland" "Use Wayland" \
        "X11" "Use X11")

        if [ -z "$DISPLAY_SERVER" ]; then
            dialog --msgbox "No display server selected. Installation cancelled." 7 50
            clear
            exit 1
        fi

        ENABLE_GUI="yes"
    else
        ENABLE_GUI="no"
        GUI_PACKAGES=""
    fi

    # Determine GUI packages based on choices
    if [[ "$ENABLE_GUI" == "yes" ]]; then
        case $GUI_CHOICE in
            "GNOME")
                if [[ "$DISPLAY_SERVER" == "X11" ]]; then
                    GUI_PACKAGES="xorg-server gnome gnome-tweaks"
                else
                    GUI_PACKAGES="gnome gnome-tweaks"
                fi
                DISPLAY_MANAGER="gdm"
            ;;
            "KDE Plasma")
                if [[ "$DISPLAY_SERVER" == "X11" ]]; then
                    GUI_PACKAGES="xorg-server plasma-meta kde-applications"
                else
                    GUI_PACKAGES="plasma-meta kde-applications"
                fi
                DISPLAY_MANAGER="sddm"
            ;;
            "XFCE")
                # XFCE primarily uses X11
                GUI_PACKAGES="xorg-server xfce4 xfce4-goodies"
                DISPLAY_MANAGER="lightdm"
                DISPLAY_SERVER="X11"
            ;;
        esac

        # Ask if they would like to install a video driver
        VIDEO_DRIVER_CHOICE=$(dialog --stdout --title "Video Driver" --menu "Would you like to install a video driver?" 15 60 5 \
        "Nvidia" "Nvidia drivers" \
        "AMD" "AMD drivers" \
        "Intel" "Intel drivers" \
        "VirtualBox" "VirtualBox guest drivers" \
        "None" "No video driver")

        if [ -z "$VIDEO_DRIVER_CHOICE" ]; then
            dialog --msgbox "No video driver selected. Installation cancelled." 7 50
            clear
            exit 1
        fi

        # Ask the user if they'd like to enable the multilib repository
        dialog --yesno "Would you like to enable the multilib repository?" 7 50
        if [ $? -eq 0 ]; then
            ENABLE_MULTILIB="yes"
        else
            ENABLE_MULTILIB="no"
        fi

        # Handle Nvidia selection
        if [[ "$VIDEO_DRIVER_CHOICE" == "Nvidia" ]]; then
            NVIDIA_DRIVER_TYPE=$(dialog --stdout --title "Nvidia Driver Type" --menu "Select Nvidia driver type:" 10 50 2 \
            "nvidia" "Proprietary Nvidia driver" \
            "nvidia-open" "Open-source Nvidia driver")

            if [ -z "$NVIDIA_DRIVER_TYPE" ]; then
                dialog --msgbox "No Nvidia driver type selected. Installation cancelled." 7 50
                clear
                exit 1
            fi

            if [[ "$NVIDIA_DRIVER_TYPE" == "nvidia" ]]; then
                VIDEO_DRIVER="nvidia nvidia-utils"
            else
                VIDEO_DRIVER="nvidia-open nvidia-utils"
            fi
        elif [[ "$VIDEO_DRIVER_CHOICE" == "AMD" ]]; then
            VIDEO_DRIVER="xf86-video-amdgpu"
        elif [[ "$VIDEO_DRIVER_CHOICE" == "Intel" ]]; then
            VIDEO_DRIVER="xf86-video-intel"
        elif [[ "$VIDEO_DRIVER_CHOICE" == "VirtualBox" ]]; then
            VIDEO_DRIVER="virtualbox-guest-utils"
        else
            VIDEO_DRIVER=""
        fi

        # Initialize VIDEO_PACKAGES
        VIDEO_PACKAGES=""

        if [[ -n "$VIDEO_DRIVER" ]]; then
            VIDEO_PACKAGES="$VIDEO_DRIVER"

            # If Nvidia is selected
            if [[ "$VIDEO_DRIVER_CHOICE" == "Nvidia" ]]; then
                # If multilib is enabled, include lib32-nvidia-utils
                if [[ "$ENABLE_MULTILIB" == "yes" ]]; then
                    VIDEO_PACKAGES="$VIDEO_PACKAGES lib32-nvidia-utils"
                fi
                # If display server is X11, include nvidia-settings
                if [[ "$DISPLAY_SERVER" == "X11" ]]; then
                    VIDEO_PACKAGES="$VIDEO_PACKAGES nvidia-settings"
                fi
            fi
        fi
    fi
else
    EDITOR_CHOICE=""
    NETWORK_PACKAGES=""
    GUI_PACKAGES=""
    VIDEO_PACKAGES=""
    ADDITIONAL_PACKAGES=""
fi

# Ask the user for a hostname
HOSTNAME=$(dialog --stdout --inputbox "Enter a hostname for your system (leave blank for random):" 8 60)

if [ -z "$HOSTNAME" ]; then
    # Generate a random hostname
    HOSTNAME="archlinux-$(openssl rand -hex 4)"
    dialog --msgbox "No hostname entered. A random hostname has been generated: $HOSTNAME" 7 60
fi

# Ask the user for their timezone
TIMEZONE=$(dialog --stdout --inputbox "Enter your timezone (e.g., 'Region/City', such as 'America/New_York'):" 8 60)

if [ -z "$TIMEZONE" ]; then
    dialog --msgbox "No timezone entered. Installation cancelled." 7 50
    clear
    exit 1
fi

# Ask the user if they'd like to use zram for swap
dialog --yesno "Would you like to use zram for swap instead of a traditional swap partition?" 7 70
if [ $? -eq 0 ]; then
    USE_ZRAM="yes"
else
    USE_ZRAM="no"
fi

if [[ "$USE_ZRAM" == "yes" ]]; then
    ZRAM_PACKAGES="zram-generator"
else
    ZRAM_PACKAGES=""
fi

# Ask if the user wants to create a new user
dialog --yesno "Would you like to create a new user account?" 7 50
if [ $? -eq 0 ]; then
    CREATE_USER="yes"
    USERNAME=$(dialog --stdout --inputbox "Enter the username for the new user:" 8 50)
    if [ -z "$USERNAME" ]; then
        dialog --msgbox "No username entered. Installation cancelled." 7 50
        clear
        exit 1
    fi

    # Ask if the user should be added to the wheel group
    dialog --yesno "Should this user have sudo privileges?" 7 50
    if [ $? -eq 0 ]; then
        ADD_TO_WHEEL="yes"
    else
        ADD_TO_WHEEL="no"
    fi
else
    CREATE_USER="no"
fi

# Get PARTUUID before chrooting
PARTUUID=$(blkid -s PARTUUID -o value $ROOT_PART)

# Pacstrap the base system
dialog --infobox "Installing base system..." 5 40
if [[ "$MINIMAL_INSTALL" == "yes" ]]; then
    pacstrap /mnt base linux linux-firmware $MICROCODE $ZRAM_PACKAGES
else
    pacstrap /mnt base linux linux-firmware $MICROCODE $EDITOR_CHOICE $NETWORK_PACKAGES $GUI_PACKAGES $VIDEO_PACKAGES $ADDITIONAL_PACKAGES $ZRAM_PACKAGES
fi

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Copy variables to a temporary file to use inside chroot
cat <<EOT > /mnt/tmp/vars.sh
TIMEZONE='$TIMEZONE'
HOSTNAME='$HOSTNAME'
MINIMAL_INSTALL='$MINIMAL_INSTALL'
ENABLE_NM='$ENABLE_NM'
ENABLE_GUI='$ENABLE_GUI'
DISPLAY_MANAGER='$DISPLAY_MANAGER'
VIDEO_DRIVER='$VIDEO_DRIVER'
ENABLE_MULTILIB='$ENABLE_MULTILIB'
USE_ZRAM='$USE_ZRAM'
MICROCODE_IMG='$MICROCODE_IMG'
PARTUUID='$PARTUUID'
CREATE_USER='$CREATE_USER'
USERNAME='$USERNAME'
ADD_TO_WHEEL='$ADD_TO_WHEEL'
EOT

# Chroot into the new system and perform configurations
arch-chroot /mnt /bin/bash <<EOF
# Load variables
source /tmp/vars.sh

# Set the time zone
ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "$HOSTNAME" > /etc/hostname
cat <<EOL >> /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
EOL

# Enable multilib repository if selected
if [[ "\$ENABLE_MULTILIB" == "yes" ]]; then
    echo "Enabling multilib repository..."
    sed -i '/\\[multilib\\]/,/Include/ s/^#//' /etc/pacman.conf
    pacman -Sy
fi

# Install bootloader
echo "Installing rEFInd bootloader..."
pacman -S --noconfirm refind

refind-install

# Update refind.conf
sed -i 's/^#extra_kernel_version_strings.*/extra_kernel_version_strings linux-hardened,linux-rt-lts,linux-zen,linux-lts,linux-rt,linux/' /boot/EFI/refind/refind.conf

# Enable mouse in rEFInd
sed -i 's/^#enable_mouse/enable_mouse/' /boot/EFI/refind/refind.conf

# Set mouse speed to 8
sed -i 's/^#mouse_speed.*/mouse_speed 8/' /boot/EFI/refind/refind.conf

# Set resolution to max
sed -i 's/^#resolution max/resolution max/' /boot/EFI/refind/refind.conf

# Enable NetworkManager if installed
if [[ "\$MINIMAL_INSTALL" == "no" && "\$ENABLE_NM" == "yes" ]]; then
    systemctl enable NetworkManager
fi

# Enable graphical target if GUI is installed
if [[ "\$MINIMAL_INSTALL" == "no" && "\$ENABLE_GUI" == "yes" ]]; then
    systemctl set-default graphical.target
    # Enable display manager
    systemctl enable \$DISPLAY_MANAGER
fi

# If VirtualBox guest utils are installed, enable the service
if [[ "\$VIDEO_DRIVER" == "virtualbox-guest-utils" ]]; then
    systemctl enable vboxservice
fi

# Configure zram if selected
if [[ "\$USE_ZRAM" == "yes" ]]; then
    echo "Configuring zram swap..."
    cat <<EOLZRAM > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOLZRAM
fi

# Set root password
echo "Please set the root password."
passwd root

# Create user if selected
if [[ "\$CREATE_USER" == "yes" ]]; then
    useradd -m "\$USERNAME"
    echo "Please set the password for user \$USERNAME."
    passwd "\$USERNAME"

    if [[ "\$ADD_TO_WHEEL" == "yes" ]]; then
        usermod -aG wheel "\$USERNAME"
        # Enable sudo for wheel group
        sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    fi
fi

# Remove temporary variables file
rm /tmp/vars.sh

EOF

# Configure /boot/refind_linux.conf with expanded variables and additional boot options
cat <<EOL > /mnt/boot/refind_linux.conf
"Boot with standard options"        "root=PARTUUID=$PARTUUID rw rootflags=subvol=@ initrd=\\$MICROCODE_IMG initrd=\\initramfs-%v.img"
"Boot with fallback initramfs"      "root=PARTUUID=$PARTUUID rw rootflags=subvol=@ initrd=\\$MICROCODE_IMG initrd=\\initramfs-%v-fallback.img"
"Boot to terminal (multi-user)"     "root=PARTUUID=$PARTUUID rw rootflags=subvol=@ initrd=\\$MICROCODE_IMG initrd=\\initramfs-%v.img systemd.unit=multi-user.target"
"Boot to single user mode"          "root=PARTUUID=$PARTUUID rw rootflags=subvol=@ initrd=\\$MICROCODE_IMG initrd=\\initramfs-%v.img single"
EOL

# Ask the user if they'd like to chroot into the system or reboot
dialog --yesno "Installation complete. Would you like to chroot into the new system?" 7 60
if [ $? -eq 0 ]; then
    dialog --msgbox "You are now entering the chroot environment. Type 'exit' to exit the chroot." 7 60
    clear
    arch-chroot /mnt
    # After exiting chroot, ask if the user wants to reboot
    dialog --yesno "Would you like to reboot now?" 7 40
    if [ $? -eq 0 ]; then
        umount -R /mnt
        reboot
    else
        dialog --msgbox "You can reboot later by typing 'reboot'. Remember to unmount the partitions if necessary." 7 70
    fi
else
    # Unmount partitions
    umount -R /mnt
    dialog --title "Installation Complete" --msgbox "Installation complete. You can reboot now." 7 50
    clear
fi
