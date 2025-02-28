#!/bin/bash
# user.sh
create_user_account() {
    local username
    while true; do
        prompt "Enter username (3-32 chars, lowercase/nums/_): " username
        [[ "$username" =~ ^[a-z_][a-z0-9_-]{2,31}$ ]] || { log "${RED}Invalid username format.${NC}"; continue; }
        grep -q "^$username:" /mnt/etc/passwd 2>/dev/null && { log "${RED}Username '$username' exists.${NC}"; continue; }
        break
    done
    log "Creating user '$username'..."
    arch-chroot /mnt useradd -m -G wheel -s "$DEFAULT_SHELL" "$username" "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
    log "Set password for '$username' (enter twice):"
    arch-chroot /mnt passwd "$username"
    if [[ "$DEFAULT_SHELL" == "/bin/zsh" ]]; then
        cat > "/mnt/home/$username/.zshrc" <<EOF
# User's shell config
alias grep='grep --color=auto'
alias ip='ip -color=auto'
PS1='%F{green}%n@%m%f:%F{blue}%~%f\$ '
EOF
    else
        cat > "/mnt/home/$username/.bashrc" <<EOF
# User's shell config
alias grep='grep --color=auto'
alias ip='ip --color=auto'
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
EOF
    fi
    echo "$username"
}

configure_sudo_access() {
    local username="$1"
    arch-chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")"
    arch-chroot /mnt visudo -c "$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")" || { log "${RED}Sudo config error!${NC}"; return 1; }
    log "Sudo access granted for '$username'."
}

setup_user_accounts() {
    log "Setting up user..."
    local new_username
    new_username=$(create_user_account) || { log "${RED}User creation failed!${NC}"; return 1; }
    configure_sudo_access "$new_username" || return 1
}
