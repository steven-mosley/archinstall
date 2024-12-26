#!/bin/bash

# Bash script to automate a minimal Hyprland setup.
#
# This is meant to be a minimal, but functional Hyprland install, while keeping the vanila experience.
# Out of the box Hyprland doesn't have a screenshot tool, clipboard manager, a status bar, or a working lock screen.
# What this ISN'T meant to be is a "complete" DM-like experience that adds extra themes and customizations.
# There are many great full Hyprland auto installs that accomplish that in the Hyprland wiki.
#
# What you'll see is still very much the default, out of the box Hyprland experience.
# Additions include:
# - App launcher
# - clipboard manager
# - notification daemon
# - session manager
# - status bar
# - screenshot tool
# - A working lock screen
# - Working power management listeners
# - All with default keybindings applied to $HOME/.config/hypr/hyprland.conf

# Todo: Add basic fonts
#     - `noto-fonts-lite` and `ttf-jetbrains-mono-nerd` are good candidates
# Fix: Address issue where hyprshot keybinds aren't being properly inserted into $HOME/.config/hypr/hyprland.conf
#     - This is likely due to the text matching logic
# Fix: Change `wofi --list drun` to `rofi -list drun` in $HOME/.config/hypr/hyprland.conf
# Feature: Create logic to parse monitor native resolution and replace `preferred` in `monitor = ,preferred,auto,auto` with that value
# Todo: Add new $HOME/.config/hypr/hyprlock.conf` config
# Todo: Add more sane default keybinds
#     - Change terminal to $modSuper T
#     - Change quit active to $modSuper Q
#     - Change float window to $modSuper $modShift V
# ...and any other QOL improvements that may come up.

set -e  # Exit on error

###############################################################################
# Basic Utility / Duplicate Removal
###############################################################################

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Deduplicate a given line in a file, leaving only the first occurrence
deduplicate_line_in_file() {
  local file="$1"
  local line="$2"

  # For deduplication, the line in the file must match exactly.
  # If the config has trailing spaces or a backslash before $, it won't match.
  awk -v needle="$line" '
    BEGIN { found=0 }
    {
      if ($0 == needle) {
        if (found == 1) {
          # This is a duplicate occurrence, so skip printing it
          next
        }
        found=1
      }
      print
    }
  ' "$file" > /tmp/dedup_temp && mv /tmp/dedup_temp "$file"
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
  echo "Installing Hyprland..."
  if [[ $AUR_HELPER == "yay" ]]; then
    $AUR_HELPER -S --needed hypridle hyprland hyprlock hyprpolkitagent \
    xdg-desktop-portal-hyprland alacritty uwsm rofi-lbonn-wayland-git \
    libnewt dunst pipewire-jack wl-clipboard hyprshot --noconfirm --removemake
  elif [[ $AUR_HELPER == "paru" ]]; then
    $AUR_HELPER -S --needed hypridle hyprland hyprlock hyprpolkitagent \
    xdg-desktop-portal-hyprland alacritty uwsm rofi-lbonn-wayland-git \
    libnewt dunst pipewire-jack wl-clipboard hyprshot --noconfirm --removemake
  else
    echo "Unsupported AUR helper: $AUR_HELPER" >&2
    exit 1
  fi
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
  sed -n 's/\$menu = wofi --show drun/\$menu = rofi -show drun/' "$HOME/.config/hypr/hyprland.conf"

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

  # Debugging: Output the generated block
  echo "Generated Hyprshot block:"
  echo "$HYPRSHOT_BLOCK"
  echo "----- End of block -----"

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
    echo "GRUB is installed. You may need to regenerate your GRUB configuration using:"
    echo "sudo grub-mkconfig -o /boot/grub/grub.cfg"
  fi
}

main
