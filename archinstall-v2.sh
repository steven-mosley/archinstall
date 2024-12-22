#!/bin/bash

# Dependency check function
check_dependencies() {
  local REQUIRED_PKGS=("dialog" "lsblk" "parted" "mkfs.ext4" "mkfs.btrfs" "cryptsetup" "btrfs-progs" "pacstrap")
  local MISSING_PKGS=()

  for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! command -v "$pkg" &>/dev/null; then
      MISSING_PKGS+=("$pkg")
    fi
  done

  if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    dialog --title "Missing Dependencies" --msgbox \
      "The following packages are missing and will be installed:\n\n${MISSING_PKGS[*]}" 15 60

    pacman -Sy --noconfirm "${MISSING_PKGS[@]}" || {
      dialog --title "Error" --msgbox "Failed to install missing dependencies. Aborting." 10 50
      exit 1
    }
  else
    dialog --title "Dependency Check" --msgbox "All required dependencies are installed!" 8 50
  fi
}

# Function to display a welcome message
welcome_screen() {
  dialog --clear \
    --backtitle "Arch Linux Installer" \
    --title "Welcome to the Arch Installer" \
    --msgbox "Welcome to the ultimate Arch Installer. Let's make your Arch dreams come true." 10 60
}

# Function to select a disk
select_disk_gui() {
  local DISK
  DISK=$(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk" {print "/dev/" $1 " (" $2 ")"}' |
    dialog --clear --menu "Select the disk to use:" 15 60 5 3>&1 1>&2 2>&3)

  if [[ -z "$DISK" ]]; then
    dialog --title "Error" --msgbox "No disk selected. Aborting." 8 40
    exit 1
  fi

  echo "$DISK"
}

# Function to select a filesystem
filesystem_gui() {
  local FS
  FS=$(dialog --clear \
    --title "Filesystem Selection" \
    --menu "Select the filesystem for your installation:" \
    15 60 4 \
    ext4 "Standard ext4 filesystem" \
    btrfs "Modern Btrfs filesystem" \
    exit "Exit installer" 3>&1 1>&2 2>&3)

  if [[ -z "$FS" || "$FS" == "exit" ]]; then
    dialog --title "Aborted" --msgbox "No filesystem selected. Exiting." 8 40
    exit 1
  fi

  echo "$FS"
}

# Function to handle encryption
setup_encryption() {
  local DISK=$1
  dialog --yesno "Do you want to encrypt $DISK with LUKS?" 8 50
  if [[ $? -eq 0 ]]; then
    local PASSPHRASE
    PASSPHRASE=$(dialog --passwordbox "Enter a passphrase for encryption:" 10 60 3>&1 1>&2 2>&3)

    if [[ -z "$PASSPHRASE" ]]; then
      dialog --title "Error" --msgbox "Passphrase cannot be empty. Aborting." 8 40
      exit 1
    fi

    dialog --infobox "Encrypting $DISK with LUKS..." 5 50
    echo "$PASSPHRASE" | cryptsetup luksFormat "$DISK"
    echo "$PASSPHRASE" | cryptsetup open "$DISK" luks-enc
    DISK="/dev/mapper/luks-enc"
  fi

  echo "$DISK"
}

# Function to create Btrfs subvolumes
setup_btrfs_subvolumes() {
  local DISK=$1
  local MOUNT_POINT=$2

  dialog --infobox "Creating Btrfs filesystem on $DISK..." 5 50
  mkfs.btrfs "$DISK"

  mkdir -p "$MOUNT_POINT"
  mount "$DISK" "$MOUNT_POINT"

  local SUBVOLS
  SUBVOLS=$(dialog --inputbox "Enter subvolumes to create (comma-separated, e.g., @,@home,@var):" 10 60 "@,@home,@var" 3>&1 1>&2 2>&3)

  IFS=',' read -r -a SUBVOL_ARRAY <<<"$SUBVOLS"
  for SUBVOL in "${SUBVOL_ARRAY[@]}"; do
    btrfs subvolume create "$MOUNT_POINT/$SUBVOL"
    dialog --infobox "Created subvolume $SUBVOL." 5 50
  done
}

# Function to display progress bar
progress_bar() {
  (
    echo "0"
    sleep 1
    echo "# Formatting disk..."
    sleep 1
    echo "25"
    mkfs.ext4 /dev/sda >/dev/null 2>&1
    echo "50"
    sleep 1
    echo "# Mounting disk..."
    sleep 1
    echo "100"
    sleep 1
  ) | dialog --title "Disk Setup Progress" --gauge "Please wait..." 10 60 0
}

# Main installer flow
main_gui() {
  # Dependency check
  check_dependencies

  # Welcome screen
  welcome_screen

  # Select disk
  local DISK=$(select_disk_gui)

  # Select filesystem
  local FS=$(filesystem_gui "$DISK")

  # Handle encryption if needed
  if [[ "$FS" != "existing" ]]; then
    DISK=$(setup_encryption "$DISK")
  fi

  # If Btrfs, create subvolumes
  if [[ "$FS" == "btrfs" ]]; then
    local MOUNT_POINT="/mnt"
    setup_btrfs_subvolumes "$DISK" "$MOUNT_POINT"
  else
    dialog --infobox "Formatting $DISK as $FS..." 5 50
    mkfs."$FS" "$DISK"
  fi

  # Display progress bar
  progress_bar

  dialog --title "Complete" --msgbox "Disk setup is complete. Proceeding to installation." 10 60
}

# Run the main function
main_gui
