#!/bin/bash

# Enable NTP synchronization
timedatectl set-ntp true

echo "Welcome to the Arch Linux Automated Installer."

# List available disks
echo "Available disks:"
lsblk -d -e 7,11 -o NAME,SIZE,TYPE

# Ask the user to choose the disk to install Arch Linux
read -p "Enter the disk to install Arch Linux (e.g., /dev/sda): " DISK

# Confirm with the user
read -p "All data on $DISK will be erased. Are you sure? [y/N]: " CONFIRM

if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
    echo "Installation cancelled."
    exit 1
fi

# Recommend BTRFS partition layout
echo -e "\nRecommended BTRFS partition layout:"
echo "- EFI System Partition (ESP): /mnt/efi"
echo "- BTRFS subvolumes:"
echo "  - @ mounted at /mnt"
echo "  - @home mounted at /mnt/home"
echo "  - @pkg mounted at /mnt/var/cache/pacman/pkg"
echo "  - @log mounted at /mnt/var/log"
echo "  - @snapshots mounted at /mnt/.snapshots"

read -p "Do you want to use the recommended BTRFS layout? [Y/n]: " USE_BTRFS

if [[ $USE_BTRFS == "n" || $USE_BTRFS == "N" ]]; then
    echo "Custom partitioning is not implemented in this script."
    echo "Please partition your disk manually and rerun the script."
    exit 1
fi

# Partition the disk
echo "Partitioning the disk..."

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
echo "Formatting the partitions..."

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
mkdir -p /mnt/{home,var/cache/pacman/pkg,var/log,.snapshots}
mount -o $MOUNT_OPTIONS,subvol=@home $ROOT_PART /mnt/home
mount -o $MOUNT_OPTIONS,subvol=@pkg $ROOT_PART /mnt/var/cache/pacman/pkg
mount -o $MOUNT_OPTIONS,subvol=@log $ROOT_PART /mnt/var/log
mount -o $MOUNT_OPTIONS,subvol=@snapshots $ROOT_PART /mnt/.snapshots

# Mount the EFI partition
mkdir -p /mnt/efi
mount $ESP /mnt/efi

# CPU Microcode
echo "Detecting CPU type..."
CPU_VENDOR=$(lscpu | grep 'Vendor ID' | awk '{print $3}')

if [[ $CPU_VENDOR == "GenuineIntel" ]]; then
    MICROCODE="intel-ucode"
    MICROCODE_IMG="intel-ucode.img"
elif [[ $CPU_VENDOR == "AuthenticAMD" ]]; then
    MICROCODE="amd-ucode"
    MICROCODE_IMG="amd-ucode.img"
else
    read -p "Unable to detect CPU microcode. Do you have an Intel or AMD CPU? [intel/amd]: " CPU_CHOICE
    if [[ $CPU_CHOICE == "intel" ]]; then
        MICROCODE="intel-ucode"
        MICROCODE_IMG="intel-ucode.img"
    elif [[ $CPU_CHOICE == "amd" ]]; then
        MICROCODE="amd-ucode"
        MICROCODE_IMG="amd-ucode.img"
    else
        echo "Invalid choice. Defaulting to no microcode."
        MICROCODE=""
        MICROCODE_IMG=""
    fi
fi

echo "Microcode selected: $MICROCODE"

# Ask if the user wants to perform a minimal install
read -p "Do you want to perform a minimal install? [y/N]: " MINIMAL_INSTALL_CHOICE
if [[ $MINIMAL_INSTALL_CHOICE == "y" || $MINIMAL_INSTALL_CHOICE == "Y" ]]; then
    MINIMAL_INSTALL="yes"
else
    MINIMAL_INSTALL="no"
fi

if [[ "$MINIMAL_INSTALL" == "no" ]]; then
    # Text editor choice
    echo "Select a text editor to install:"
    select EDITOR_CHOICE in vi vim nano; do
        case $EDITOR_CHOICE in
            vi|vim|nano)
                break
                ;;
            *)
                echo "Invalid selection."
                ;;
        esac
    done

    # NetworkManager installation
    read -p "Would you like to install NetworkManager to manage network connections? [Y/n]: " INSTALL_NM

    if [[ $INSTALL_NM == "n" || $INSTALL_NM == "N" ]]; then
        NETWORK_PACKAGES=""
        ENABLE_NM="no"
    else
        NETWORK_PACKAGES="networkmanager"
        ENABLE_NM="yes"
    fi

    # Ask for additional packages
    read -p "Enter any additional packages to install during pacstrap (separated by spaces), or press Enter to skip: " ADDITIONAL_PACKAGES

    # Ask the user if they want to install a GUI
    echo "Would you like to install a GUI/Desktop Environment?"
    select GUI_CHOICE in "GNOME" "KDE Plasma" "XFCE" "None"; do
        case $GUI_CHOICE in
            "GNOME"|"KDE Plasma")
                GUI_DE="$GUI_CHOICE"
                break
                ;;
            "XFCE")
                GUI_DE="XFCE"
                break
                ;;
            "None")
                GUI_DE="None"
                break
                ;;
            *)
                echo "Invalid selection."
                ;;
        esac
    done

    if [[ "$GUI_DE" != "None" ]]; then
        # Prompt for Wayland or X11
        echo "Do you want to use Wayland or X11?"
        select DISPLAY_SERVER in "Wayland" "X11"; do
            case $DISPLAY_SERVER in
                "Wayland")
                    break
                    ;;
                "X11")
                    break
                    ;;
                *)
                    echo "Invalid selection."
                    ;;
            esac
        done
        ENABLE_GUI="yes"
    else
        ENABLE_GUI="no"
        GUI_PACKAGES=""
    fi

    # Determine GUI packages based on choices
    if [[ "$ENABLE_GUI" == "yes" ]]; then
        case $GUI_DE in
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
        echo "Would you like to install a video driver?"
        select VIDEO_DRIVER_CHOICE in "Nvidia" "AMD" "Intel" "VirtualBox" "None"; do
            case $VIDEO_DRIVER_CHOICE in
                "Nvidia")
                    # Ask for Nvidia driver type
                    echo "Select Nvidia driver type:"
                    select NVIDIA_DRIVER_TYPE in "nvidia" "nvidia-open"; do
                        case $NVIDIA_DRIVER_TYPE in
                            "nvidia")
                                VIDEO_DRIVER="nvidia nvidia-utils"
                                break
                                ;;
                            "nvidia-open")
                                VIDEO_DRIVER="nvidia-open nvidia-utils"
                                break
                                ;;
                            *)
                                echo "Invalid selection."
                                ;;
                        esac
                    done
                    break
                    ;;
                "AMD")
                    VIDEO_DRIVER="xf86-video-amdgpu"
                    break
                    ;;
                "Intel")
                    VIDEO_DRIVER="xf86-video-intel"
                    break
                    ;;
                "VirtualBox")
                    VIDEO_DRIVER="virtualbox-guest-utils"
                    break
                    ;;
                "None")
                    VIDEO_DRIVER=""
                    break
                    ;;
                *)
                    echo "Invalid selection."
                    ;;
            esac
        done

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
fi

# Ask the user for a hostname
read -p "Enter a hostname for your system: " HOSTNAME

# Ask the user for their timezone
echo "Available time zones can be found under /usr/share/zoneinfo."
read -p "Enter your timezone (e.g., 'Region/City', such as 'America/New_York'): " TIMEZONE

# Ask the user if they'd like to enable the multilib repository
read -p "Would you like to enable the multilib repository? [y/N]: " ENABLE_MULTILIB_CHOICE
if [[ $ENABLE_MULTILIB_CHOICE == "y" || $ENABLE_MULTILIB_CHOICE == "Y" ]]; then
    ENABLE_MULTILIB="yes"
else
    ENABLE_MULTILIB="no"
fi

# Pacstrap the base system
echo "Installing base system..."
if [[ "$MINIMAL_INSTALL" == "yes" ]]; then
    pacstrap /mnt base linux linux-firmware $MICROCODE
else
    pacstrap /mnt base linux linux-firmware $MICROCODE $EDITOR_CHOICE $NETWORK_PACKAGES $GUI_PACKAGES $VIDEO_PACKAGES $ADDITIONAL_PACKAGES
fi

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF
# Set the time zone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "$HOSTNAME" > /etc/hostname
echo -e "127.0.0.1\tlocalhost
::1\t\tlocalhost
127.0.1.1\t$HOSTNAME.localdomain\t$HOSTNAME" >> /etc/hosts

# Enable multilib repository if selected
if [[ "$ENABLE_MULTILIB" == "yes" ]]; then
    echo "Enabling multilib repository..."
    sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
    pacman -Sy
fi

# Set root password
echo "Setting root password:"
passwd root

# Install bootloader
echo "Installing rEFInd bootloader..."
pacman -S --noconfirm refind

refind-install

# Configure /boot/refind_linux.conf
PARTUUID=\$(blkid -s PARTUUID -o value $ROOT_PART)
echo '"Boot with standard options"    "root=PARTUUID=\$PARTUUID rw rootflags=subvol=@ initrd=@\\boot\\$MICROCODE_IMG initrd=@\\boot\\initramfs-%v.img"' > /boot/refind_linux.conf

# Update refind.conf
sed -i 's/^#extra_kernel_version_strings.*/extra_kernel_version_strings linux-hardened,linux-rt-lts,linux-zen,linux-lts,linux-rt,linux/' /efi/EFI/refind/refind.conf

# Enable NetworkManager if installed
if [[ "$MINIMAL_INSTALL" == "no" && "$ENABLE_NM" == "yes" ]]; then
    systemctl enable NetworkManager
fi

# Enable graphical target if GUI is installed
if [[ "$MINIMAL_INSTALL" == "no" && "$ENABLE_GUI" == "yes" ]]; then
    systemctl set-default graphical.target
    # Enable display manager
    systemctl enable $DISPLAY_MANAGER
fi

# If VirtualBox guest utils are installed, enable the service
if [[ "$VIDEO_DRIVER" == "virtualbox-guest-utils" ]]; then
    systemctl enable vboxservice
fi

EOF

# Unmount partitions
umount -R /mnt

echo "Installation complete. You can reboot now."
