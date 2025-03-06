#!/usr/bin/env python3
# System configuration module

import os
import subprocess
import getpass
from modules.utils import log, error, prompt, run_command, show_progress

def configure_system(default_locale, default_tz, selected_disk, uefi_mode):
    """Configure basic system settings in the installed system"""
    log("Configuring system settings...")

    try:
        # Set hostname
        hostname = input("Enter hostname: ")
        with open("/mnt/etc/hostname", "w") as f:
            f.write(f"{hostname}\n")
        
        # Configure hosts file
        with open("/mnt/etc/hosts", "w") as f:
            f.write(f"127.0.0.1\tlocalhost\n")
            f.write(f"::1\t\tlocalhost\n")
            f.write(f"127.0.1.1\t{hostname}.localdomain\t{hostname}\n")

        # Configure locale
        log(f"Configuring locale: {default_locale}")
        # Uncomment the locale in locale.gen
        run_command(f"sed -i '/#*{default_locale}/s/^#//' /mnt/etc/locale.gen")
        show_progress("Generating locales", f"arch-chroot /mnt locale-gen")
        
        with open("/mnt/etc/locale.conf", "w") as f:
            f.write(f"LANG={default_locale}\n")

        # Configure timezone
        log(f"Configuring timezone: {default_tz}")
        run_command(f"arch-chroot /mnt ln -sf /usr/share/zoneinfo/{default_tz} /etc/localtime")
        run_command("arch-chroot /mnt hwclock --systohc")

        # Configure network
        log("Setting up network configuration...")
        if prompt("Do you want to use NetworkManager instead of dhcpcd?"):
            show_progress("Installing NetworkManager", "arch-chroot /mnt pacman -S --noconfirm networkmanager")
            show_progress("Enabling NetworkManager service", "arch-chroot /mnt systemctl enable NetworkManager")
            log("NetworkManager enabled")
        else:
            show_progress("Installing dhcpcd", "arch-chroot /mnt pacman -S --noconfirm dhcpcd")
            show_progress("Enabling dhcpcd service", "arch-chroot /mnt systemctl enable dhcpcd")
            log("dhcpcd enabled")

        # Configure bootloader
        install_bootloader(selected_disk, uefi_mode)

        log("System configuration completed")
        return True
    except Exception as e:
        error(f"Failed to configure system: {str(e)}")
        return False

def set_system_clock():
    """Set the system clock"""
    log("Setting system clock...")
    
    try:
        # Enable network time synchronization
        subprocess.check_call(["timedatectl", "set-ntp", "true"])
        
        # Wait for time sync
        log("Waiting for time synchronization...")
        for i in range(3):  # Try up to 3 times
            status = subprocess.run(
                ["timedatectl", "status"], 
                stdout=subprocess.PIPE,
                text=True
            ).stdout
            
            if "synchronized: yes" in status:
                log("Time synchronized successfully")
                break
            elif i < 2:
                log("Waiting for time sync...")
                subprocess.run(["sleep", "1"])
        
        return True
    except subprocess.CalledProcessError as e:
        log(f"Warning: Could not set system clock: {str(e)}")
        log("Continuing installation without time synchronization")
        return True  # Continue despite errors

def install_bootloader(selected_disk, uefi_mode):
    """Install and configure bootloader"""
    log("Installing and configuring bootloader")
    
    try:
        if uefi_mode:
            log("Installing GRUB for UEFI system")
            show_progress("Installing GRUB packages", "arch-chroot /mnt pacman -S --noconfirm grub efibootmgr", exit_on_error=True)
            show_progress("Installing GRUB bootloader", "arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH", exit_on_error=True)
        else:
            log("Installing GRUB for BIOS system")
            show_progress("Installing GRUB package", "arch-chroot /mnt pacman -S --noconfirm grub", exit_on_error=True)
            show_progress("Installing GRUB bootloader", f"arch-chroot /mnt grub-install --target=i386-pc {selected_disk}", exit_on_error=True)
        
        # Generate GRUB configuration
        show_progress("Generating GRUB configuration", "arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg", exit_on_error=True)
        
        log("Bootloader installed successfully")
        return True
    except Exception as e:
        error(f"Failed to install bootloader: {str(e)}")
        return False

def setup_network():
    """Configure basic network settings"""
    log("Setting up basic network configuration")
    
    # Ensure network configs are copied to new system
    try:
        os.makedirs("/mnt/etc/systemd/network", exist_ok=True)
        
        # Copy resolv.conf for DNS resolution
        if os.path.exists("/etc/resolv.conf"):
            run_command("cp /etc/resolv.conf /mnt/etc/resolv.conf")
        
        return True
    except Exception as e:
        log(f"Warning: Could not copy network configuration: {str(e)}")
        return False

def setup_user_accounts(default_shell):
    """Set up user accounts and sudo access"""
    log("Setting up user accounts...")
    
    try:
        # Set root password
        log("Setting root password...")
        
        # Try up to 3 times to set password
        for attempt in range(3):
            if run_command("arch-chroot /mnt passwd root", show_output=True):
                break
            if attempt == 2:
                error("Failed to set root password after multiple attempts")
                return False
        
        # Create user account
        username = input("Enter username for new user: ")
        
        if not username:
            error("Username cannot be empty")
            return False
        
        log(f"Creating user: {username}")
        run_command(f'arch-chroot /mnt useradd -m -G wheel -s "/bin/{default_shell}" "{username}"')
        
        # Set user password
        log(f"Setting password for {username}...")
        for attempt in range(3):
            if run_command(f'arch-chroot /mnt passwd "{username}"', show_output=True):
                break
            if attempt == 2:
                error(f"Failed to set password for {username} after multiple attempts")
                return False
        
        # Configure sudo
        log("Configuring sudo access...")
        run_command("arch-chroot /mnt pacman -S --noconfirm sudo")
        
        with open("/mnt/etc/sudoers.d/wheel", "w") as f:
            f.write("%wheel ALL=(ALL) ALL\n")
        
        os.chmod("/mnt/etc/sudoers.d/wheel", 0o440)
        
        # Ask for additional packages
        if prompt("Do you want to install additional packages?"):
            additional_packages = input("Enter package names (separated by spaces): ")
            
            if additional_packages:
                log(f"Installing additional packages: {additional_packages}")
                show_progress("Installing additional packages", f'arch-chroot /mnt pacman -S --noconfirm {additional_packages}')
        else:
            log("No additional packages requested")
        
        log("User accounts created successfully")
        return True
    except Exception as e:
        error(f"Failed to set up user accounts: {str(e)}")
        return False