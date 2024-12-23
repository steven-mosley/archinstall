#!/bin/bash

# Bash script to automate Hyprland setup with all requested utilities and configurations
# Written for the picky configuration overlord you are.

# Exit on error
set -e

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to check and install dependencies
check_dependencies() {
  echo "Checking for dependencies..."
  DEPENDENCIES=("git" "base-devel")
  MISSING_PACKAGES=()

  for package in "${DEPENDENCIES[@]}"; do
    if ! pacman -Qi "$package" &>/dev/null; then
      MISSING_PACKAGES+=("$package")
    else
      echo "$package is already installed."
    fi
  done

  if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    echo "Installing missing dependencies: ${MISSING_PACKAGES[*]}..."
    sudo pacman -S --needed "${MISSING_PACKAGES[@]}" --noconfirm
  else
    echo "All dependencies are already installed!"
  fi
}

# Function to install or select AUR helper
aur_helper_setup() {
  if ! command_exists yay && ! command_exists paru; then
    echo "Neither yay nor paru found. Prompting for installation choice."
    echo "Select your preferred AUR helper:"
    select CHOICE in "yay" "paru"; do
      case $CHOICE in
      yay)
        echo "Installing yay"
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        cd /tmp/yay
        makepkg -si --noconfirm
        cd -
        AUR_HELPER="yay"
        break
        ;;
      paru)
        echo "Installing paru"
        git clone https://aur.archlinux.org/paru.git /tmp/paru
        cd /tmp/paru
        makepkg -si --noconfirm
        cd -
        AUR_HELPER="paru"
        break
        ;;
      *)
        echo "Invalid choice. Please select either 'yay' or 'paru'."
        ;;
      esac
    done
  else
    AUR_HELPER=$(command_exists yay && echo "yay" || echo "paru")
  fi

  echo "Using AUR helper: $AUR_HELPER"
}

# Function to enable multilib repo
enable_multilib() {
  if grep -q "^#\[multilib\]" /etc/pacman.conf; then
    echo "Uncommenting [multilib] repo..."
    sudo sed -i '/^#\[multilib\]/s/^#//' /etc/pacman.conf
    sudo sed -i '/^#Include = \/etc\/pacman.d\/mirrorlist/s/^#//' /etc/pacman.conf
    sudo pacman -Syu --noconfirm
  elif ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "Adding [multilib] repo..."
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf
    sudo pacman -Syu --noconfirm
  else
    echo "[multilib] repo is already enabled."
  fi
}

# Function to set up NVIDIA drivers
nvidia_setup() {
  if lspci | grep -i nvidia >/dev/null 2>&1; then
    echo "NVIDIA card detected. Performing NVIDIA configuration..."
    $AUR_HELPER -S --needed nvidia-dkms linux-headers nvidia-utils lib32-nvidia-utils egl-wayland libva-nvidia-driver
    sudo sed -i 's/^MODULES=.*$/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<EOF
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

    echo "Checking for NVIDIA hibernation services..."
    nvidia_services=("nvidia-hibernate.service" "nvidia-suspend.service" "nvidia-resume.service")
    nvidia_service_not_enabled=()
    for service in "${nvidia_services[@]}"; do
      if ! systemctl is-enabled "$service" &>/dev/null; then
        nvidia_service_not_enabled+=("$service")
      else
        echo "$service is already enabled."
      fi
    done

    if [[ ${#nvidia_service_not_enabled[@]} -gt 0 ]]; then
      echo "Found NVIDIA services not enabled."
      echo "Enabling: ${nvidia_service_not_enabled[*]}..."
      sudo systemctl enable "${nvidia_service_not_enabled[@]}"
    else
      echo "All NVIDIA services are already enabled."
    fi

    UWSM_DIR="$HOME/.config/uwsm"
    UWSM_ENV="$UWSM_DIR/env"
    UWSM_ENV_HYPRLAND="$UWSM_DIR/env-hyprland"

    if [[ ! -e "$UWSM_DIR" ]]; then
      mkdir -p "$UWSM_DIR"
      tee "$UWSM_ENV" >/dev/null <<EOF
export LIBVA_DRIVER_NAME=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export NVD_BACKEND=direct
export ELECTRON_OZONE_PLATFORM_HINT=auto
EOF
    fi

  else
    echo "No NVIDIA card detected. Skipping NVIDIA setup."
  fi
}

# Function to install Hyprland
install_hyprland() {
  echo "Installing Hyprland..."
  $AUR_HELPER -S --needed hyprland-meta-git alacritty uwsm
}

# Function to set up Hypridle
configure_hyprland() {
  echo "Configuring Hyprland..."
  mkdir -p "$HOME/.config/hypr"
  curl -o "$HOME/.config/hypr/hyprland.conf" https://raw.githubusercontent.com/hyprwm/Hyprland/main/example/hyprland.conf
  sed -i 's/kitty/alacritty/' "$HOME/.config/hypr/hyprland.conf"
  sed -i 's/dolphin/null/' "$HOME/.config/hypr/hyprland.conf"
  echo "Checking to see if hyprpolkitagent.service is enabled..."
  if ! systemctl --user is-enabled hyprpolkitagent.service; then
    echo "Enabling hyprpolkitagent.service..."
    systemctl --user enable hyprpolkitagent.service
  else
    echo "hyprpolkitagent.service is already enabled."
  fi
}

setup_powermanagement() {
  mkdir -p "$HOME/.config/hypr"
  tee "$HOME/.config/hypr/hypridle.conf" >/dev/null <<EOF
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch dpms on
}

listener {
    timeout = 150
    on-timeout = brightnessctl -s set 10
    on-resume = brightnessctl -r
}

listener {
    timeout = 300
    on-timeout = loginctl lock-session
}

listener {
    timeout = 330
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on
}

listener {
    timeout = 1800
    on-timeout = systemctl suspend
}
EOF
  # Function to set up Hyprlock
  mkdir -p "$HOME/.config/hypr"
  tee "$HOME/.config/hypr/hyprlock.conf" >/dev/null <<EOF
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
    font_color = rgb(143, 143, 143)
    placeholder_text = Password
}

label {
    monitor =
    text = $USER
    color = rgba(200, 200, 200, 1.0)
    font_size = 25
    halign = center
    valign = center
}
EOF

  echo "Checking to see if hypridle.service is enabled..."
  if ! systemctl --user is-enabled hypridle.service; then
    echo "Enabling hypridle.service..."
    systemctl enable --user hypridle.service
  else
    echo "hypridle.service is already enabled."
  fi
}

display_hyprland_info() {
  # Define color codes
  bold=$(tput bold)
  reset=$(tput sgr0)
  green=$(tput setaf 2)
  blue=$(tput setaf 4)
  yellow=$(tput setaf 3)
  cyan=$(tput setaf 6)
  red=$(tput setaf 1)

  cat <<EOF
  
██╗  ██╗██╗   ██╗██████╗ ██████╗ ██╗      █████╗ ███╗   ██╗██████╗ 
██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗██║     ██╔══██╗████╗  ██║██╔══██╗
███████║ ╚████╔╝ ██████╔╝██████╔╝██║     ███████║██╔██╗ ██║██║  ██║
██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗██║     ██╔══██║██║╚██╗██║██║  ██║
██║  ██║   ██║   ██║     ██║  ██║███████╗██║  ██║██║ ╚████║██████╔╝
╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ 
                                                                   
${bold}${green}Hyprland Installation Complete!${reset}
${cyan}A minimum install has been performed with a few exceptions:${reset}
- ${yellow}The basic Hyprland config has been modified to use Alacritty instead of Kitty.${reset}
  ${blue}Alacritty is more lightweight and better suited for tiling desktops.${reset}
- ${yellow}A basic config has been set up for Hypridle and Hyprlock.${reset}
  ${blue}Power management will now lock the screen and suspend after 5 minutes by default.${reset}

${bold}${green}Universal Wayland Session Manager (uwsm)${reset} has been configured to ${red}auto-start${reset} upon logging in to the tty. 
It will prompt you to select a compositor. 
To start using Hyprland, select the ${bold}${yellow}Hyprland${reset} option ${red}without "uwsm-managed."${reset}

${bold}${cyan}You can disable this by removing the following lines from your shell configuration:${reset} ($HOME/.bashrc or $HOME/.zshrc)
${yellow}if uwsm check may-start && uwsm select; then${reset}
${yellow}  exec systemd-cat -t uwsm uwsm start default${reset}
${yellow}fi${reset}

${red}Be warned:${reset} ${bold}Disabling uwsm may break some functionality as this install is optimized for uwsm.${reset}

${bold}${cyan}Recommended Method:${reset}
Using ${bold}uwsm${reset} to manage Hyprland ensures proper ${green}systemctl${reset} integration for services like:
- ${yellow}hypeidle${reset}
- ${yellow}hyprpolkitagent${reset}
- ${yellow}waybar${reset}
- ${blue}...and much of the rest of the Hypr* ecosystem.${reset}

${bold}${cyan}Alternative Method:${reset}
If you prefer not to use uwsm, set these services to autostart in your ${yellow}$HOME/.config/hypr/hyprland.conf${reset} file using the ${cyan}exec-once directive.${reset}

${bold}${cyan}Other Options:${reset}
You may use a display manager (DM) such as ${yellow}SDDM${reset} or ${yellow}GDM${reset}, but ${bold}uwsm${reset} remains the recommended way to manage your Hyprland session.

${bold}${green}Installed Hyprland Packages:${reset}
EOF

  # Fetch and display installed Hyprland packages
  if ! $AUR_HELPER -Qs hyprland; then
    echo -e "${red}No Hyprland packages detected! Something might have gone wrong during the installation.${reset}"
  fi

  cat <<EOF

${bold}${cyan}Recommended Additional Packages:${reset}
- ${yellow}App Launcher:${reset} rofi-lbonn-wayland-git
- ${yellow}Status Bar:${reset} waybar
- ${yellow}Clipboard Tools:${reset} clipse, wl-clipboard
- ${yellow}Notification Daemon:${reset} dunst
- ${yellow}Screenshot Tool:${reset} hyprshot
- ${yellow}Wayland Libraries:${reset} qt5-wayland, qt6-wayland
- ${yellow}Audio Server:${reset} pipewire, wireplumber

${bold}${green}Next Steps:${reset}
Reboot your system, log in to the tty, and select ${yellow}Hyprland${reset} from the ${green}uwsm prompt${reset} to start your ${cyan}Wayland journey.${reset}

EOF
}

# Main function to execute all other functions
main() {
  check_dependencies
  aur_helper_setup
  enable_multilib
  nvidia_setup
  install_hyprland
  configure_hyprland
  setup_powermanagement
  display_hyprland_info
}

# Execute the main function
main
