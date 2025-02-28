#!/bin/bash
# System configuration module

# Configure basic system settings in the installed system
configure_system() {
    log "Configuring system settings..."

    # Set hostname
    read -r -p "Enter hostname: " hostname
    echo "$hostname" > /mnt/etc/hostname
    
    # Configure hosts file
    cat > /mnt/etc/hosts <<EOF
127.0.0.1	localhost
::1		localhost
127.0.1.1	$hostname.localdomain	$hostname
EOF

    # Configure locale
    log "Configuring locale: $DEFAULT_LOCALE"
    sed -i "/#$DEFAULT_LOCALE/s/^#//" /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=$DEFAULT_LOCALE" > /mnt/etc/locale.conf

    # Configure timezone
    log "Configuring timezone: $DEFAULT_TZ"
    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$DEFAULT_TZ" /etc/localtime
    arch-chroot /mnt hwclock --systohc

    # Configure network
    log "Setting up network configuration..."
    if prompt "Do you want to use NetworkManager instead of dhcpcd?"; then
        arch-chroot /mnt pacman -S --noconfirm networkmanager
        arch-chroot /mnt systemctl enable NetworkManager
        log "NetworkManager enabled"
    else
        arch-chroot /mnt pacman -S --noconfirm dhcpcd
        arch-chroot /mnt systemctl enable dhcpcd
        log "dhcpcd enabled"
    fi

    # Configure bootloader
    install_bootloader

    log "System configuration completed"
}

# Function to install and configure bootloader
install_bootloader() {
    log "Installing and configuring bootloader"
    
    # Install GRUB and other necessary packages
    if [[ "$UEFI_MODE" -eq 1 ]]; then
        log "Installing GRUB for UEFI system"
        arch-chroot /mnt pacman -S --noconfirm grub efibootmgr
        arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=ARCH
    else
        log "Installing GRUB for BIOS system"
        arch-chroot /mnt pacman -S --noconfirm grub
        arch-chroot /mnt grub-install --target=i386-pc "$selected_disk"
    fi
    
    # Generate GRUB configuration
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    
    log "Bootloader installed successfully"
}

# Function to install base packages
install_base_system() {
    log "Installing base Arch Linux system..."
    
    # Create basic packages list
    local packages="base linux linux-firmware sudo vim"
    
    # Add additional packages
    if [[ "$UEFI_MODE" -eq 1 ]]; then
        packages="$packages efibootmgr"
    fi
    
    # Add microcode packages based on CPU
    if grep -q "AuthenticAMD" /proc/cpuinfo; then
        log "AMD CPU detected, adding AMD microcode"
        packages="$packages amd-ucode"
    elif grep -q "GenuineIntel" /proc/cpuinfo; then
        log "Intel CPU detected, adding Intel microcode"
        packages="$packages intel-ucode"
    fi
    
    # Install packages
    log "Installing packages: $packages"
    pacstrap /mnt $packages
    
    log "Base system installed"
}

# Function to set up user accounts
setup_user_accounts() {
    log "Setting up user accounts..."
    
    # Ask for additional packages
    if prompt "Do you want to install additional packages?"; then
        read -r -p "Enter package names (separated by spaces): " additional_packages
        
        if [[ -n "$additional_packages" ]]; then
            log "Installing additional packages: $additional_packages"
            arch-chroot /mnt pacman -S --noconfirm $additional_packages
        fi
    else
        log "No additional packages requested"
    fi
    
    # Setup shell preference
    read -r -p "Enter preferred shell (default: bash): " shell_choice
    shell_choice=${shell_choice:-bash}
    if [[ -n "$shell_choice" && "$shell_choice" != "bash" ]]; then
        log "Setting up $shell_choice as default shell"
        arch-chroot /mnt pacman -S --noconfir