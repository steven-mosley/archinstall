#!/bin/bash

# Bash script to automate Hyprland setup with all requested utilities and configurations
# Written for the picky configuration overlord you are.

set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Step 0: Check for sudo and user privileges
if ! command_exists sudo; then
    echo "sudo is not installed. Installing it now, you reckless fuck..."
    if command_exists pacman; then
        su -c "pacman -S --needed sudo --noconfirm" || {
            echo "Failed to install sudo. Run this script as root or a competent user!"
            exit 1
        }
    else
        echo "No package manager found to install sudo. You're on your own, dumbass."
        exit 1
    fi
fi

if ! sudo -l >/dev/null 2>&1; then
    echo "You don't have sudo privileges, you peasant!"
    echo "Run this script as a user with sudo permissions or switch to a real admin account."
    exit 1
fi

# Step 1: Check for git and base-devel
echo "Checking for dependencies, you unprepared bastard..."
MISSING_PACKAGES=()
for package in git base-devel; do
    if ! pacman -Qi $package &>/dev/null; then
        MISSING_PACKAGES+=("$package")
    fi
done

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    echo "Installing missing dependencies: ${MISSING_PACKAGES[*]}..."
    sudo pacman -S --needed ${MISSING_PACKAGES[*]} --noconfirm
fi

# Step 2: Install or select AUR helper
if ! command_exists yay && ! command_exists paru; then
    echo "Neither yay nor paru found. Prompting for installation choice."

    if ! command_exists whiptail; then
        echo "Installing whiptail for TUI menu..."
        sudo pacman -S --needed libnewt --noconfirm
    fi

    CHOICE=$(whiptail --title "AUR Helper Selection" \
        --menu "Select your preferred AUR helper:" 15 60 2 \
        "yay" "The OG, stable choice for AUR users." \
        "paru" "The newer kid on the block with modern features." \
        3>&1 1>&2 2>&3)

    case $CHOICE in
    yay)
        echo "Installing yay the proper way, you impatient bastard..."
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        cd /tmp/yay
        makepkg -si --noconfirm
        cd -
        AUR_HELPER="yay"
        ;;
    paru)
        echo "Installing paru the proper way, you lazy shit..."
        git clone https://aur.archlinux.org/paru.git /tmp/paru
        cd /tmp/paru
        makepkg -si --noconfirm
        cd -
        AUR_HELPER="paru"
        ;;
    *)
        echo "No valid choice made. Exiting, jackass!"
        exit 1
        ;;
    esac
else
    AUR_HELPER=$(command_exists yay && echo "yay" || echo "paru")
fi

echo "Using AUR helper: $AUR_HELPER"

# Step 3: Enable multilib repo
echo "Ensuring multilib repo is enabled..."
if ! grep -q "\[multilib\]" /etc/pacman.conf; then
    echo "[multilib]" | sudo tee -a /etc/pacman.conf
    echo "Include = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf
    sudo pacman -Syu --noconfirm
fi

# Step 4: Install Hyprland and extra packages
echo "Installing Hyprland meta package and extras..."
$AUR_HELPER -S --needed hyprland-meta-git kitty rofi-lbonn-wayland-git waybar \
    clipse dunst wl-clipboard wl-clip-persist hyprshot otf-font-awesome uwsm qt5-wayland qt6-wayland

# Enable Waybar service
echo "Enabling waybar.service..."
systemctl --user enable --now waybar.service

# Copy basic Waybar config
echo "Copying Waybar config..."
mkdir -p ~/.config/waybar
cp -r /etc/xdg/waybar/* ~/.config/waybar/

# Step 5: NVIDIA setup (if applicable)
if lspci | grep -i nvidia >/dev/null 2>&1; then
    echo "NVIDIA card detected. Setting up drivers and configuration..."
    $AUR_HELPER -S --needed nvidia-dkms linux-headers nvidia-utils lib32-nvidia-utils egl-wayland libva-nvidia-driver

    echo "Updating /etc/mkinitcpio.conf for DRM kernel mode..."
    sudo sed -i 's/^MODULES=.*$/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sudo mkinitcpio -P

    echo "Configuring /etc/modprobe.d/nvidia.conf..."
    sudo bash -c "cat <<EOF > /etc/modprobe.d/nvidia.conf
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF"

    echo "Enabling NVIDIA services..."
    sudo systemctl enable nvidia-hibernate.service nvidia-suspend.service nvidia-resume.service
else
    echo "No NVIDIA card detected. Skipping NVIDIA setup, genius."
fi

# Step 6: Basic Hyprland config
echo "Setting up Hyprland example config..."
mkdir -p ~/.config/hypr
curl -o ~/.config/hypr/hyprland.conf https://raw.githubusercontent.com/hyprwm/Hyprland/main/example/hyprland.conf

# Replace wofi with rofi in hyprland.conf
echo "Updating hyprland.conf to use rofi..."
sed -i 's/wofi --show drun/rofi -show drun/' ~/.config/hypr/hyprland.conf

# Add clipse and dunst to the AUTOSTART section
echo "Adding clipse and dunst to the AUTOSTART section in hyprland.conf..."
sed -i '/^### AUTOSTART ###$/a \
# Autostart necessary processes (like notifications daemons, status bars, etc.)\n\
exec-once = clipse -listen\n\
exec-once = dunst' ~/.config/hypr/hyprland.conf

# Step 7: Set up Hyprlock configuration
echo "Creating Hyprlock configuration..."
cat <<EOF > ~/.config/hypr/hyprlock.conf
background {
    monitor =
    path = screenshot
    color = rgba(25, 20, 20, 1.0)
    blur_passes = 2
}

input-field {
    monitor =
    size = 20%, 5%
    outline_thickness = 3
    inner_color = rgba(0, 0, 0, 0.0)

    outer_color = rgba(33ccffee) rgba(00ff99ee) 45deg
    check_color = rgba(00ff99ee) rgba(ff6633ee) 120deg
    fail_color = rgba(ff6633ee) rgba(ff0066ee) 40deg

    font_color = rgb(143, 143, 143)
    fade_on_empty = false
    rounding = 15

    position = 0, -20
    halign = center
    valign = center

    placeholder_text = Password
}

label {
    monitor =
    text = \$USER
    color = rgba(200, 200, 200, 1.0)
    font_size = 25
    font_family = Noto Sans

    position = 0, 80
    halign = center
    valign = center
}
EOF

# Step 8: Enable Hypridle and Hyprlock services
echo "Enabling Hypridle and Hyprlock services..."
systemctl --user enable --now hypridle.service

echo "Installation complete! Reboot and log in via uwsm, you glorious bastard!"
