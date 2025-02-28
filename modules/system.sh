#!/usr/bin/env bash
# System configuration module

# Function to check boot media
check_boot_media() {
    log "Checking boot media..."
    if [[ "$UNSUPPORTED" -eq 0 ]] && lsblk | grep -q "sr0"; then
        log "Detected live CD/USB media. Installation can proceed."
    else
        log "Warning: This doesn't seem to be running from Arch installation media."
        if [[ "$UNSUPPORTED" -eq 0 ]]; then
            log "Use --unsupported-boot-media to override this check."
            exit 1
        else
            log "Proceeding anyway as requested."
        fi
    fi
}

# Function to check UEFI mode
check_uefi() {
    log "Checking boot mode..."
    if [ -d /sys/firmware/efi/efivars ]; then
        log "UEFI mode detected."
    else
        log "Error: UEFI mode not detected. This installer requires UEFI."
        exit 1
    fi
}

# Function to install base system
install_base_system() {
    log "Installing base system packages..."
    
    # Format partitions
    local efi_partition="${selected_disk}1"
    local root_partition="${selected_disk}2"
    
    mkfs.fat -F32 "$efi_partition" || return 1
    mkfs.ext4 "$root_partition" || return 1
    
    # Mount partitions
    mount "$root_partition" /mnt || return 1
    mkdir -p /mnt/boot/efi
    mount "$efi_partition" /mnt/boot/efi || return 1
    
    # Install base system
    pacstrap /mnt base linux linux-firmware base-devel || return 1
    
    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab || return 1
    
    log "Base system installed successfully."
    return 0
}

# Function to configure system
configure_system() {
    log "Configuring system settings..."
    
    # Set timezone
    if [[ -z "${DEFAULT_TZ:-}" ]]; then
        prompt "Enter timezone (e.g., America/New_York): " timezone
    else
        timezone="$DEFAULT_TZ"
        log "Using default timezone: $timezone"
    fi
    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime || exit 1
    arch-chroot /mnt hwclock --systohc || exit 1
    
    # Set locale
    if [[ -z "${DEFAULT_LOCALE:-}" ]]; then
        prompt "Enter locale (e.g., en_US.UTF-8): " locale
    else
        locale="$DEFAULT_LOCALE"
        log "Using default locale: $locale"
    fi
    sed -i "s/^#$locale/$locale/" /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen || exit 1
    echo "LANG=$locale" > /mnt/etc/locale.conf
    
    # Configure bootloader (systemd-boot)
    arch-chroot /mnt pacman -S --noconfirm efibootmgr || exit 1
    arch-chroot /mnt bootctl install || exit 1
    
    # Create loader entry
    mkdir -p /mnt/boot/loader/entries
    cat > /mnt/boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=${selected_disk}2 rw
EOF
    
    log "System configuration complete."
}

# Function to set up user accounts
setup_user_accounts() {
    log "Setting up user accounts..."
    
    # Set root password
    log "Setting root password:"
    arch-chroot /mnt passwd || return 1
    
    # Create user
    prompt "Enter username: " username
    arch-chroot /mnt useradd -m -G wheel "$username" || return 1
    
    log "Setting password for $username:"
    arch-chroot /mnt passwd "$username" || return 1
    
    # Configure sudo
    arch-chroot /mnt pacman -S --noconfirm sudo || return 1
    echo "%wheel ALL=(ALL) ALL" > /mnt/etc/sudoers.d/wheel
    chmod 440 /mnt/etc/sudoers.d/wheel
    
    # Set default shell
    if [[ -n "${DEFAULT_SHELL:-}" ]]; then
        log "Setting $DEFAULT_SHELL as default shell for $username"
        arch-chroot /mnt pacman -S --noconfirm "$DEFAULT_SHELL" || log "Failed to install $DEFAULT_SHELL"
        arch-chroot /mnt chsh -s "/bin/$DEFAULT_SHELL" "$username" || log "Failed to change shell"
    fi
    
    log "User accounts configured successfully."
    return 0
}

# Function for cleanup operations
cleanup() {
    log "Performing final cleanup..."
    
    # Unmount partitions
    umount -R /mnt || log "Warning: Failed to unmount some partitions"
    
    log "Installation completed successfully!"
    log "You can now reboot into your new Arch Linux system."
}

# Function to set timezone
set_timezone() {
    log "Setting timezone to $DEFAULT_TZ..."
    # Logic to set timezone
    return 0
}

# Function to set locale
set_locale() {
    log "Setting locale to $DEFAULT_LOCALE..."
    # Logic to set locale
    return 0
}

# Function to set keymap
set_keymap() {
    log "Setting keymap..."
    # Logic to set keymap
    return 0
}

# Function to install bootloader
install_bootloader() {
    log "Installing bootloader..."
    # Logic to install and configure bootloader
    return 0
}

# Function to configure sudo access
configure_sudo() {
    log "Configuring sudo access..."
    # Logic to set up sudo
    return 0
}

# Function to set default shell
set_shell() {
    log "Setting default shell to $DEFAULT_SHELL..."
    # Logic to set default shell
    return 0
}
