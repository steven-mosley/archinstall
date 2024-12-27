#!/bin/bash

# Check if running with sudo/root permissions
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

set -e  # Exit on error

###############################################################################
# Basic Utility / Duplicate Removal
###############################################################################

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

###############################################################################
# 1) Microcode
###############################################################################
microcode() {
  echo "Checking CPU type for microcode installation..."
  if lscpu | grep -i "intel" >/dev/null 2>&1; then
    echo "Intel CPU detected. Checking for intel-ucode..."
    if ! pacman -Qi intel-ucode &>/dev/null; then
      echo "Installing intel-ucode..."
      sudo pacman -S --needed intel-ucode --noconfirm
    else
      echo "intel-ucode is already installed."
    fi
  elif lscpu | grep -i "amd" >/dev/null 2>&1; then
    echo "AMD CPU detected. Checking for amd-ucode..."
    if ! pacman -Qi amd-ucode &>/dev/null; then
      echo "Installing amd-ucode..."
      sudo pacman -S --needed amd-ucode --noconfirm
    else
      echo "amd-ucode is already installed."
    fi
  else
    echo "Unknown CPU type. Skipping microcode installation."
  fi
}

###############################################################################
# 2) Check Dependencies
###############################################################################
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

###############################################################################
# 3) AUR Helper Setup
###############################################################################
aur_helper_setup() {
  if ! command_exists yay && ! command_exists paru; then
    echo "Neither yay nor paru found. Prompting for installation choice."
    echo "Select your preferred AUR helper:"
    select CHOICE in "yay" "paru"; do
      case $CHOICE in
        yay)
          echo "Installing yay..."
          git clone https://aur.archlinux.org/yay.git /tmp/yay
          cd /tmp/yay
          makepkg -si --noconfirm
          cd -
          AUR_HELPER="yay"
          break
          ;;
        paru)
          echo "Installing paru..."
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
    if command_exists yay; then
      AUR_HELPER="yay"
    elif command_exists paru; then
      AUR_HELPER="paru"
    fi
  fi

  echo "Using AUR helper: $AUR_HELPER"
}

###############################################################################
# 4) Enable Multilib
###############################################################################
enable_multilib() {
# Define the file path
  PACMAN_CONF="/etc/pacman.conf"

  # Check if [multilib] section exists (commented or uncommented)
  if grep -q '\[multilib\]' "$PACMAN_CONF"; then
      # Section exists, just uncomment it
      sed -i -e '/^#\[multilib\]/,+1 s/^#//' "$PACMAN_CONF"
      echo "Existing multilib repository has been enabled"
  else
      # Section doesn't exist, append it
      echo -e "\n# If you want to run 32 bit applications on your x86_64 system,\n# enable the multilib repository.\n\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> "$PACMAN_CONF"
      echo "Multilib repository has been added and enabled"
  fi
}

###############################################################################
# 5) NVIDIA Setup
###############################################################################
nvidia_setup() {
  if lspci | grep -i nvidia >/dev/null 2>&1; then
    echo "NVIDIA card detected. Performing NVIDIA configuration..."
    $AUR_HELPER -S --needed nvidia-dkms linux-headers nvidia-utils lib32-nvidia-utils egl-wayland libva-nvidia-driver --noconfirm --removemake

    sudo sed -i '/^MODULES=/s/=.*/=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf

    sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<EOF
options nvidia_drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

    if [[ ! -f "$HOME/.config/uwsm/env" ]]; then
      mkdir -p "$HOME/.config/uwsm"
      tee "$HOME/.config/uwsm/env" >/dev/null <<EOF
export NVD_BACKEND=direct
export ELECTRON_OZONE_PLATFORM_HINT=auto
export LIBVA_DRIVER_NAME=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia # Comment out if screen sharing is blank in apps
EOF
    fi

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
      echo "Enabling: ${nvidia_service_not_enabled[*]}..."
      sudo systemctl enable "${nvidia_service_not_enabled[@]}"
    else
      echo "All NVIDIA services are already enabled."
    fi
  else
    echo "No NVIDIA card detected. Skipping NVIDIA setup."
  fi
}

###############################################################################
# 6) Install Hyprland
###############################################################################
install_hyprland() {
  echo "Installing core Hyprland packages..."
  $AUR_HELPER -S --needed hyprland --noconfirm --removemake
  
  # Prompt the user to decide on installing extras
  read -p "Would you like to install extras? (y/n): " install_extras
  if [[ "$install_extras" == "y" || "$install_extras" == "Y" ]]; then
    install_hyprland_extras
  else
    echo "Skipped installing extras."
  fi
}

install_hyprland_extras() {
  $AUR_HELPER -S --needed hyprpolkitagent hypridle hyprlock hyprshot \
  xdg-desktop-portal-hyprland xdg-user-dirs alacritty uwsm rofi-lbonn-wayland-git \
  libnewt dunst pipewire-jack --noconfirm --removemake
}

###############################################################################
# 7) Base Hyprland Config
###############################################################################
configure_hyprland() {
  echo "Configuring Hyprland..."
  mkdir -p "$HOME/.config/hypr"

  if [[ ! -f "$HOME/.config/hypr/hyprland.conf" ]]; then
    curl -o "$HOME/.config/hypr/hyprland.conf" \
      https://raw.githubusercontent.com/hyprwm/Hyprland/main/example/hyprland.conf
  fi

  sed -i 's/kitty/alacritty/' "$HOME/.config/hypr/hyprland.conf"
  sed -i 's/dolphin/null/' "$HOME/.config/hypr/hyprland.conf"
  sed -n 's/wofi --show drun/rofi -show drun/' "$HOME/.config/hypr/hyprland.conf"

  if ! systemctl --user is-enabled hyprpolkitagent.service &>/dev/null; then
    echo "Enabling hyprpolkitagent.service..."
    systemctl --user enable hyprpolkitagent.service
  else
    echo "hyprpolkitagent.service is already enabled."
  fi

  for shell_profile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$shell_profile" ]]; then
      echo "Ensuring uwsm auto-start is in $shell_profile..."
      grep -q 'uwsm check may-start' "$shell_profile" || cat >>"$shell_profile" <<'EOF'
if uwsm check may-start && uwsm select; then
  exec systemd-cat -t uwsm_start uwsm start default
fi
EOF
    fi
  done
}

###############################################################################
# 10) Hyprshot Config (Block Insertion + Deduplication)
###############################################################################
configure_hyprshot_binds() {
  local HYPRCONF="$HOME/.config/hypr/hyprland.conf"
  echo "Configuring Hyprshot key bindings in hyprland.conf..."

  local MARKER='bindl = , XF86AudioPrev, exec, playerctl previous'

  # Use already defined modifiers
  local LINE_WIN="bind = , PRINT, exec, hyprshot -m window"
  local LINE_MON="bind = $mainMod SHIFT, PRINT, exec, hyprshot -m output"
  local LINE_REG="bind = $mainMod, PRINT, exec, hyprshot -m region"

  # Construct the Hyprshot block (ensure correct multiline handling)
  local HYPRSHOT_BLOCK
  HYPRSHOT_BLOCK=$(cat <<EOF
# Screenshot a window
$LINE_WIN
# Screenshot a monitor
$LINE_MON
# Screenshot a region
$LINE_REG
EOF
)

  # Check if Hyprshot block already exists
  if grep -Fxq "$LINE_WIN" "$HYPRCONF"; then
    echo "Hyprshot key bindings already exist. Skipping block insertion."
  else
    # Append the block after the specific line containing the marker
    if grep -Fq "$MARKER" "$HYPRCONF"; then
      echo "Inserting Hyprshot block after '$MARKER'..."

      # Check if the file is writable
      if [ ! -w "$HYPRCONF" ]; then
        echo "Error: $HYPRCONF is not writable. Exiting..."
        return 1
      fi

      # Append after the marker using `sed`
      sed -i "/$MARKER/a\\
# Hyprshot key bindings\\
$LINE_WIN\\
$LINE_MON\\
$LINE_REG\\
" "$HYPRCONF"

      echo "Hyprshot block successfully inserted after '$MARKER'."
    else
      echo "Marker '$MARKER' not found in $HYPRCONF. Appending block at the end..."

      # If the marker is not found, append at the end of the file
      {
        echo -e "\n# Hyprshot key bindings"
        echo "$HYPRSHOT_BLOCK"
      } >> "$HYPRCONF"

      echo "Hyprshot block successfully appended at the end of $HYPRCONF."
    fi

    # Display the final contents of the config file
    echo "Final contents of $HYPRCONF:"
    cat "$HYPRCONF"
  fi
}

###############################################################################
# 11) Power Management
###############################################################################
setup_powermanagement() {
  mkdir -p "$HOME/.config/hypr"
  tee "$HOME/.config/hypr/hypridle.conf" >/dev/null <<EOF
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch dpms on
}

listener {
    timeout = 600
    on-timeout = loginctl lock-session
}

listener {
    timeout = 630
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on
}

listener {
    timeout = 1800
    on-timeout = systemctl suspend
}
EOF

  if ! systemctl --user is-enabled hypridle.service &>/dev/null; then
    echo "Enabling hypridle.service..."
    systemctl enable --user hypridle.service
  else
    echo "hypridle.service is already enabled."
  fi
}

###############################################################################
# 12) Main
###############################################################################
main() {
  microcode
  check_dependencies
  aur_helper_setup
  enable_multilib
  nvidia_setup
  install_hyprland
  configure_hyprland
  configure_hyprshot_binds
  setup_powermanagement

  echo "Running mkinitcpio to regenerate initramfs..."
  sudo mkinitcpio -P

  if pacman -Qi grub &>/dev/null; then
    grub-mkconfig -o /boot/grub/grub.cfg
  fi
}

main
