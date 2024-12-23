#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

# Install dialog if not present
pacman-key --init
pacman -Sy --needed --noconfirm dialog

# Temporary files
TMP_DISK=/tmp/disk_selection
TMP_PART=/tmp/partition_selection
TMP_METHOD=/tmp/part_method
TMP_ERR=/tmp/error_log
TMP_OUT=/tmp/output_log
TMP_SUMMARY=/tmp/summary_log

# Clean up temporary files on exit
trap 'rm -f $TMP_DISK $TMP_PART $TMP_METHOD $TMP_ERR $TMP_OUT $TMP_SUMMARY' EXIT

create_disk_menu() {
  local menu_items=()
  while read -r line; do
    local name size model
    name=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $4}')
    model=$(echo "$line" | awk '{$1=$2=$3=$4=""; print $0}' | sed 's/^ *//')
    menu_items+=("$name" "$size - $model")
  done < <(lsblk -d -p -n -o NAME,MAJ:MIN,RM,SIZE,MODEL | grep -v "loop")

  dialog --clear --title "Disk Selection" \
    --menu "Select disk to partition:\n(Use arrow keys and Enter to select)" \
    20 70 10 "${menu_items[@]}" 2>"$TMP_DISK"
}

create_partition_menu() {
  dialog --clear --title "Partition Method" \
    --menu "Choose partitioning method:" 15 60 4 \
    "noob_ext4" "Automatic partitioning with ext4" \
    "noob_btrfs" "Automatic partitioning with BTRFS" \
    "manual" "Manual partitioning (using cfdisk)" \
    2>"$TMP_METHOD"
}

do_partition() {
  local disk=$1
  local choice=$2

  # Ensure disk is ready
  umount -R "$disk" 2>/dev/null || true
  swapoff "$disk"* 2>/dev/null || true

  case $choice in
  "noob_ext4")
    # Create GPT partition table
    parted -s "$disk" mklabel gpt
    echo 10

    # Create EFI partition (512MB)
    parted -s "$disk" mkpart primary fat32 1MiB 513MiB
    parted -s "$disk" set 1 esp on
    echo 20

    # Create swap (RAM size + 2GB)
    local ram_size=$(free -m | awk '/^Mem:/{print $2}')
    local swap_size=$((ram_size / 2))
    parted -s "$disk" mkpart primary linux-swap 513MiB "$((513 + swap_size))MiB"
    echo 30

    # Create root partition (rest of disk)
    parted -s "$disk" mkpart primary ext4 "$((513 + swap_size))MiB" 100%
    echo 40

    sleep 1 # Give kernel time to recognize new partitions

    # Format partitions (with automatic yes to prompts)
    echo y | mkfs.fat -F32 "${disk}1"
    echo 50
    echo y | mkswap "${disk}2"
    swapon "${disk}2"
    echo 60
    echo y | mkfs.ext4 "${disk}3"
    echo 70

    # Mount partitions
    mount "${disk}3" /mnt
    mkdir -p /mnt/efi
    mount "${disk}1" /mnt/efi
    echo 100
    ;;

  "noob_btrfs")
    # Create GPT partition table
    parted -s "$disk" mklabel gpt
    echo 10

    # Create EFI partition (512MB)
    parted -s "$disk" mkpart primary fat32 1MiB 513MiB
    parted -s "$disk" set 1 esp on
    echo 20

    # Create swap (RAM size + 2GB)
    local ram_size=$(free -m | awk '/^Mem:/{print $2}')
    local swap_size=$((ram_size / 2))
    parted -s "$disk" mkpart primary linux-swap 513MiB "$((513 + swap_size))MiB"
    echo 30

    # Create root partition (rest of disk)
    parted -s "$disk" mkpart primary btrfs "$((513 + swap_size))MiB" 100%
    echo 40

    sleep 1 # Give kernel time to recognize new partitions

    # Format partitions
    local os_name=$(hostnamectl | awk -F': ' '/Operating System/{print $2}' | cut -d' ' -f1)
    echo y | mkfs.fat -F32 "${disk}1"
    echo 50
    echo y | mkswap "${disk}2"
    swapon "${disk}2"
    echo 60
    echo y | mkfs.btrfs -L ${os_name} -f "${disk}3"
    echo 70

    # Create and mount BTRFS subvolumes
    mount "${disk}3" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@pkg
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/@snapshots
    echo 80

    umount /mnt
    mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@ "${disk}3" /mnt
    mkdir -p /mnt/{efi,home,var/cache/pacman/pkg,var/log,.snapshots}
    mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@home "${disk}3" /mnt/home
    mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@pkg "${disk}3" /mnt/var/cache/pacman/pkg
    mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@log "${disk}3" /mnt/var/log
    mount -o noatime,compress=zstd,discard=async,space_cache=v2,subvol=@snapshots "${disk}3" /mnt/.snapshots
    mount "${disk}1" /mnt/efi
    echo 100
    ;;

  "manual")
    cfdisk "$disk"
    echo 100
    ;;
  esac
}

install_base_system() {
  pacstrap /mnt base linux linux-firmware 2>"$TMP_ERR" | tee -a "$TMP_OUT"
  genfstab -U /mnt >>/mnt/etc/fstab
}

configure_system() {
  # Create temporary files for selections
  local TMP_LOCALE=$(mktemp)
  local TMP_HOSTNAME=$(mktemp)

  # Get available locales
  grep -E "^#[a-z]" /usr/share/i18n/SUPPORTED | cut -d' ' -f1 | sort >"$TMP_LOCALE.list"
  local locale_items=()
  while IFS= read -r locale; do
    locale_items+=("$locale" "")
  done <"$TMP_LOCALE.list"

  # Let user select locale
  dialog --clear --title "Locale Selection" \
    --menu "Select your locale:" 20 70 10 \
    "${locale_items[@]}" 2>"$TMP_LOCALE"
  local selected_locale=$(cat "$TMP_LOCALE")

  # Get hostname
  dialog --clear --title "Hostname" \
    --inputbox "Enter your system's hostname:" 8 60 "archlinux" 2>"$TMP_HOSTNAME"
  local selected_hostname=$(cat "$TMP_HOSTNAME")

  # Prompt for root password
  local TMP_ROOT_PASSWORD=$(mktemp)
  dialog --clear --title "Root Password" \
    --passwordbox "Enter root password:" 8 60 2>"$TMP_ROOT_PASSWORD"
  local root_password=$(cat "$TMP_ROOT_PASSWORD")

  # Clean up temporary files
  rm -f "$TMP_LOCALE" "$TMP_LOCALE.list" "$TMP_HOSTNAME" "$TMP_ROOT_PASSWORD"

  # Pass variables into arch-chroot
  arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/US/Central /etc/localtime
hwclock --systohc
sed -i "s/^#${selected_locale}/${selected_locale}/" /etc/locale.gen
locale-gen
echo "LANG=${selected_locale}" > /etc/locale.conf
echo "${selected_hostname}" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${selected_hostname}.localdomain ${selected_hostname}
HOSTS
mkinitcpio -P
echo -e "${root_password}\n${root_password}" | passwd
EOF
}

generate_summary() {
  local start_time=$1
  local end_time=$(date +%s)
  local elapsed_time=$((end_time - start_time))
  local minutes=$((elapsed_time / 60))
  local seconds=$((elapsed_time % 60))

  echo "Installation Summary" >"$TMP_SUMMARY"
  echo "====================" >>"$TMP_SUMMARY"
  echo "" >>"$TMP_SUMMARY"
  echo "Packages Installed:" >>"$TMP_SUMMARY"
  grep -oP '(?<=installing ).*' "$TMP_OUT" >>"$TMP_SUMMARY"
  echo "" >>"$TMP_SUMMARY"
  echo "Partitions Created:" >>"$TMP_SUMMARY"
  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT >>"$TMP_SUMMARY"
  echo "" >>"$TMP_SUMMARY"
  echo "Time Taken: ${minutes} minutes and ${seconds} seconds" >>"$TMP_SUMMARY"
  echo "" >>"$TMP_SUMMARY"
  echo "Installation complete. You can now reboot." >>"$TMP_SUMMARY"
}

main() {
  create_disk_menu || exit 1
  selected_disk=$(cat "$TMP_DISK")

  dialog --yesno "Warning: This will erase all data on $selected_disk. Continue?" 10 50 || exit 1

  create_partition_menu || exit 1
  selected_method=$(cat "$TMP_METHOD")

  start_time=$(date +%s)

  (
    do_partition "$selected_disk" "$selected_method" 2>"$TMP_ERR" || {
      dialog --textbox "$TMP_ERR" 20 70
      exit 1
    }
  ) | dialog --gauge "Partitioning and formatting disk..." 10 70 0

  dialog --programbox "Installing base system, this may take a while..." 20 70 < <(
    install_base_system 2>"$TMP_ERR" | tee -a "$TMP_OUT" || {
      dialog --textbox "$TMP_ERR" 20 70
      exit 1
    }
  )

  dialog --programbox "Configuring system, this may take a while..." 20 70 < <(
    configure_system 2>"$TMP_ERR" | tee -a "$TMP_OUT" || {
      dialog --textbox "$TMP_ERR" 20 70
      exit 1
    }
  )

  generate_summary "$start_time"

  dialog --title "Installation Summary" --yes-label "Reboot" --no-label "Terminal" --yesno "$(cat $TMP_SUMMARY)" 20 70
  if [[ $? -eq 0 ]]; then
    reboot
  else
    clear
    echo "You can now perform custom post-install operations."
  fi
}

main
