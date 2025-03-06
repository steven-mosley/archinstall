#!/usr/bin/env python3
# System check functions

import subprocess
import platform
import os
from modules.utils import log, error, run_command, TEST_MODE

def check_architecture():
    """Check if architecture is supported"""
    arch = platform.machine()
    
    if arch not in ["x86_64", "aarch64"]:
        if TEST_MODE:
            log(f"WARNING: Unsupported architecture {arch}. Continuing in test mode.")
            return True
        else:
            error(f"Unsupported architecture: {arch}")
            return False
    
    log(f"Architecture {arch} is supported")
    return True

def check_boot_media():
    """Check if running from appropriate boot media"""
    # Simplified check - in real implementation, verify Arch boot media
    if not os.path.exists('/run/archiso'):
        if TEST_MODE:
            log("WARNING: Not running from Arch installation media. Continuing in test mode.")
            return True
        else:
            error("Not running from Arch installation media.")
            return False
    
    log("Running from valid Arch installation media")
    return True

def check_internet():
    """Check internet connectivity"""
    try:
        if run_command("ping -c 1 archlinux.org", exit_on_error=False):
            log("Internet connection successful")
            return True
        else:
            if TEST_MODE:
                log("WARNING: No internet connection. Continuing in test mode.")
                return True
            else:
                error("No internet connection. Please connect to the internet before installing.")
                return False
    except:
        if TEST_MODE:
            log("WARNING: Error checking internet connection. Continuing in test mode.")
            return True
        else:
            error("Error checking internet connection.")
            return False

def check_uefi():
    """Check if system is booted in UEFI mode"""
    uefi_mode = os.path.isdir('/sys/firmware/efi')
    
    if uefi_mode:
        log("System booted in UEFI mode")
    else:
        log("System booted in BIOS mode")
    
    return uefi_mode

def optimize_mirrors():
    """Update and optimize pacman mirrors"""
    log("Updating and optimizing pacman mirrors...")
    
    # Check if reflector is installed
    if run_command("pacman -Q reflector", exit_on_error=False):
        # Run reflector to update mirrors
        run_command("reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist", 
                   exit_on_error=False,
                   show_output=True)
        log("Mirrors updated")
    else:
        log("Reflector not installed, skipping mirror optimization")
    
    # Ensure the pacman keyring is initialized
    run_command("pacman-key --init", exit_on_error=False, show_output=True)
    run_command("pacman-key --populate archlinux", exit_on_error=False, show_output=True)
    
    return True