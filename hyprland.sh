#!/bin/bash

# Bash script to automate Hyprland setup with all requested utilities and configurations
# Written for the picky configuration overlord you are.

# Exit on error
set -e

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to check and install microcode
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
  # If neither yay nor paru exists, prompt user to choose
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
    # If one of them is already installed, pick that automatically
    if command_exists yay; then
      AUR_HELPER="yay"
    elif command_exists paru; then
      AUR_HELPER="paru"
    fi
  fi

  echo "Using AUR helper: $AUR_HELPER"
}

# Function to enable multilib repo
enable_multilib() {
  if grep -Pzo "(?s)^#\[multilib\]\n#Include = /etc/pacman.d/mirrorlist" /etc/pacman.conf >/dev/null; then
    echo "Uncommenting [multilib] repo..."
    sudo sed -i '/^#\[multilib\]/s/^#//' /etc/pacman.conf
    sudo sed -i '/^#Include = \/etc\/pacman.d\/mirrorlist/s/^#//' /etc/pacman.conf
    sudo pacman -Syu --noconfirm
  elif ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "Adding [multilib] repo..."
    sudo tee -a /etc/pacman.conf >/dev/null <<EOF
[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    sudo pacman -Syu --noconfirm
  else
    echo "[multilib] repo is already enabled."
  fi
}

# Function to set up NVIDIA drivers
nvidia_setup() {
  if lspci | grep -i nvidia >/dev/null 2>&1; then
    echo "NVIDIA card detected. Performing NVIDIA configuration..."
    $AUR_HELPER -S --needed nvidia-dkms linux-headers nvidia-utils lib32-nvidia-utils egl-wayland libva-nvidia-driver --noconfirm --removemake

    sudo sed -i '/^MODULES=/s/=.*/=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf

    sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<EOF
options nvidia_drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

    # Create the UWSM env file if not exists
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

# Function to install Hyprland
install_hyprland() {
  echo "Installing Hyprland..."
  if [[ $AUR_HELPER == "yay" ]]; then
    $AUR_HELPER -S --needed hyprland-meta-git alacritty uwsm rofi-lbonn-wayland-git libnewt dunst \
      pipewire wireplumber pipewire-jack qt5-wayland qt6-wayland wl-clipboard waybar clipse hyprshot \
      --noconfirm --removemake
  elif [[ $AUR_HELPER == "paru" ]]; then
    $AUR_HELPER -S --needed hyprland-meta-git alacritty uwsm rofi-lbonn-wayland-git libnewt dunst \
      pipewire wireplumber pipewire-jack qt5-wayland qt6-wayland wl-clipboard waybar clipse hyprshot \
      --noconfirm --removemake
  else
    echo "Unsupported AUR helper: $AUR_HELPER" >&2
    exit 1
  fi
}

# Function to configure Hyprland
configure_hyprland() {
  echo "Configuring Hyprland..."
  mkdir -p "$HOME/.config/hypr"
  # Pull a sample hyprland.conf if not already present
  if [[ ! -f "$HOME/.config/hypr/hyprland.conf" ]]; then
    curl -o "$HOME/.config/hypr/hyprland.conf" \
      https://raw.githubusercontent.com/hyprwm/Hyprland/main/example/hyprland.conf
  fi

  # Replace kitty with alacritty
  sed -i 's/kitty/alacritty/' "$HOME/.config/hypr/hyprland.conf"
  # Replace dolphin with null (from example)
  sed -i 's/dolphin/null/' "$HOME/.config/hypr/hyprland.conf"

  # Enable hyprpolkitagent.service if not enabled
  if ! systemctl --user is-enabled hyprpolkitagent.service &>/dev/null; then
    echo "Enabling hyprpolkitagent.service..."
    systemctl --user enable hyprpolkitagent.service
  else
    echo "hyprpolkitagent.service is already enabled."
  fi

  # Add uwsm auto-start to shell profiles
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

# Copy /etc/xdg/waybar to ~/.config/waybar
configure_waybar() {
  echo "Copying default Waybar config to $HOME/.config/waybar/ ..."
  mkdir -p "$HOME/.config/waybar"
  cp -r /etc/xdg/waybar/* "$HOME/.config/waybar/" 2>/dev/null || true
}

# Configure clipse in hyprland.conf
configure_clipse() {
  local HYPRCONF="$HOME/.config/hypr/hyprland.conf"
  echo "Configuring Clipse in hyprland.conf..."

  # Add exec-once = clipse -listen beneath the # exec-once = waybar ... line
  sed -i '/# exec-once = waybar & hyprpaper & firefox/a exec-once = clipse -listen' "$HYPRCONF"

  # Add bind = SUPER, V, exec ... below $mainMod = SUPER # ...
  sed -i '/\$mainMod = SUPER # Sets "Windows" key as main modifier/a bind = SUPER, V, exec, alacritty --class clipse -e clipse' "$HYPRCONF"

  # Append clipse window rules to the end of the file
  {
    echo ""
    echo "windowrulev2 = float, class:(clipse)"
    echo "windowrulev2 = size 622 652, class:(clipse)"
  } >> "$HYPRCONF"
}

# Insert hyprshot binds into hyprland.conf
configure_hyprshot_binds() {
  local HYPRCONF="$HOME/.config/hypr/hyprland.conf"
  echo "Configuring Hyprshot key bindings in hyprland.conf..."

  # We'll insert these lines above "# Move focus with mainMod + arrow keys"
  # If that line doesn't exist, we just append them at the end.
  local HYPRSHOT_LINES
  HYPRSHOT_LINES=$(
    cat <<EOF
# Screenshot a window
bind = \$mainMod, PRINT, exec, hyprshot -m window
# Screenshot a monitor
bind = , PRINT, exec, hyprshot -m output
# Screenshot a region
bind = \$shiftMod, PRINT, exec, hyprshot -m region
EOF
  )

  # To avoid repeating these lines on subsequent runs, let's do a quick check:
  if ! grep -q "bind = \$mainMod, PRINT, exec, hyprshot -m window" "$HYPRCONF"; then
    if grep -q "# Move focus with mainMod + arrow keys" "$HYPRCONF"; then
      sed -i "/# Move focus with mainMod + arrow keys/i $HYPRSHOT_LINES\n" "$HYPRCONF"
    else
      echo -e "\n$HYPRSHOT_LINES" >> "$HYPRCONF"
    fi
  else
    echo "Hyprshot key bindings already exist. Skipping re-insertion."
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

  if ! systemctl --user is-enabled hypridle.service &>/dev/null; then
    echo "Enabling hypridle.service..."
    systemctl enable --user hypridle.service
  else
    echo "hypridle.service is already enabled."
  fi
}

# Main function to execute all other functions
main() {
  microcode
  check_dependencies
  aur_helper_setup
  enable_multilib
  nvidia_setup
  install_hyprland
  configure_hyprland
  configure_waybar         # Copy /etc/xdg/waybar/* -> ~/.config/waybar/
  configure_clipse         # Insert Clipse lines in hyprland.conf
  configure_hyprshot_binds # Insert Hyprshot binds in hyprland.conf
  setup_powermanagement

  echo "Running mkinitcpio to regenerate initramfs..."
  sudo mkinitcpio -P

  if pacman -Qi grub &>/dev/null; then
    echo "GRUB is installed. You may need to regenerate your GRUB configuration using:"
    echo "  sudo grub-mkconfig -o /boot/grub/grub.cfg"
  fi
}

# Execute the main function
main
