# system.sh
install_base_system() {
    mountpoint -q /mnt || { log "${RED}/mnt not mounted!${NC}"; return 1; }
    prompt "Use zsh instead of bash? (y/n): " use_zsh
    [[ "$use_zsh" =~ ^[Yy] ]] && DEFAULT_SHELL="/bin/zsh"
    log "Installing base system..."
    pacstrap -K /mnt base linux linux-firmware sudo "${DEFAULT_SHELL##*/}" $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1") &
    spinner $! "Downloading packages"
    [[ "$partition_choice" == "auto_btrfs" ]] && pacstrap -K /mnt btrfs-progs $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
    genfstab -U /mnt >> /mnt/etc/fstab 2>/dev/null
}

setup_network() {
    mountpoint -q /mnt || { log "${RED}/mnt not mounted!${NC}"; return 1; }
    log "Configuring network..."
    arch-chroot /mnt pacman -S --noconfirm networkmanager $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
    arch-chroot /mnt systemctl enable NetworkManager.service $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
}

configure_system() {
    mountpoint -q /mnt || { log "${RED}/mnt not mounted!${NC}"; return 1; }
    log "Configuring system..."
    echo -e "${YELLOW}Select locale (default: $DEFAULT_LOCALE):${NC}" > /dev/tty
    echo "1) en_US.UTF-8" > /dev/tty
    echo "2) en_GB.UTF-8" > /dev/tty
    echo "3) fr_FR.UTF-8" > /dev/tty
    echo "4) de_DE.UTF-8" > /dev/tty
    prompt "Choose (1-4, Enter for default): " locale_choice
    case "$locale_choice" in
        2) selected_locale="en_GB.UTF-8" ;;
        3) selected_locale="fr_FR.UTF-8" ;;
        4) selected_locale="de_DE.UTF-8" ;;
        *) selected_locale="$DEFAULT_LOCALE" ;;
    esac
    echo "$selected_locale UTF-8" > /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
    echo "LANG=$selected_locale" > /mnt/etc/locale.conf
    prompt "Enter hostname: " hostname
    echo "$hostname" > /mnt/etc/hostname
    { echo "127.0.0.1    localhost"; echo "::1          localhost"; echo "127.0.1.1    $hostname.localdomain $hostname"; } > /mnt/etc/hosts
    local tz=$(curl -s https://ipapi.co/timezone || echo "$DEFAULT_TZ")
    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
    arch-chroot /mnt hwclock --systohc $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
    log "Set root password (enter twice):"
    arch-chroot /mnt passwd
    prompt "Install GRUB (y) or systemd-boot (n)? (y/n): " bootloader
    if [[ "$bootloader" =~ ^[Yy] ]]; then
        log "Installing GRUB..."
        arch-chroot /mnt pacman -S --noconfirm grub efibootmgr $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
        arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
    else
        log "Installing systemd-boot..."
        arch-chroot /mnt pacman -S --noconfirm systemd-boot $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
        arch-chroot /mnt bootctl install $([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
    fi
}

cleanup() {
    log "Cleaning up..."
    umount -R /mnt 2>/dev/null || true
    swapoff -a 2>/dev/null || true
}
