#!/bin/bash
# checks.sh
check_boot_media() {
    [[ -d /run/archiso || $UNSUPPORTED -eq 1 ]] && return 0
    log "${RED}ERROR: Unofficial boot media. Use --unsupported-boot-media to proceed.${NC}"
    exit 1
}

check_internet() {
    log "Checking internet..."
    ping -c 1 archlinux.org "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")" || { log "${RED}No internet connection!${NC}"; exit 1; }
}

check_uefi() {
    [[ -d /sys/firmware/efi ]] || { log "${RED}Not in UEFI mode!${NC}"; exit 1; }
    log "UEFI mode confirmed."
}

optimize_mirrors() {
    log "Optimizing mirrors..."
    pacman -S --noconfirm reflector "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
    reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")" &
    spinner $! "Updating mirrors"
    pacman -Syy "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
}
