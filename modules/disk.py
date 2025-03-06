#!/usr/bin/env python3
# Disk management functions

import os
import subprocess
import re
from pathlib import Path
from modules.utils import log, error, prompt, run_command, validate_input, show_progress

def get_available_disks():
    """Return a list of available disks with their details"""
    disks = []
    
    # Get list of block devices
    try:
        lsblk_output = subprocess.check_output(
            ["lsblk", "-dno", "NAME,SIZE,MODEL"], 
            universal_newlines=True
        ).strip()
        
        for line in lsblk_output.split('\n'):
            if line:
                parts = line.strip().split(maxsplit=2)
                if len(parts) >= 2:
                    name = parts[0]
                    size = parts[1]
                    model = parts[2] if len(parts) > 2 else "Unknown"
                    
                    # Ignore loop devices
                    if not name.startswith("loop"):
                        disks.append({
                            "device": f"/dev/{name}",
                            "size": size,
                            "model": model,
                            "name": name
                        })
        
        return disks
    except subprocess.CalledProcessError:
        error("Failed to get available disks")
        return []

def create_disk_menu():
    """Create a menu for disk selection"""
    disks = get_available_disks()
    
    if not disks:
        error("No available disks found")
        return None
    
    print("\nAvailable disks:")
    for i, disk in enumerate(disks, 1):
        print(f"{i}. {disk['device']} ({disk['size']}) - {disk['model']}")
    
    while True:
        try:
            choice = input("\nSelect a disk (number): ")
            choice_idx = int(choice) - 1
            
            if 0 <= choice_idx < len(disks):
                selected_disk = disks[choice_idx]['device']
                
                # Confirm selection
                if prompt(f"You selected {selected_disk}. This will ERASE ALL DATA on this disk. Continue?"):
                    log(f"Selected disk: {selected_disk}")
                    return selected_disk
                else:
                    print("Disk selection cancelled. Please choose again.")
            else:
                print("Invalid selection. Please try again.")
        except ValueError:
            print("Please enter a number.")

def verify_disk_space(disk_path):
    """Verify disk has enough space for installation"""
    MIN_SPACE_GB = 20  # Minimum required space in GB
    
    try:
        # Get disk size in bytes
        size_output = subprocess.check_output(
            ["blockdev", "--getsize64", disk_path],
            universal_newlines=True
        ).strip()
        
        size_bytes = int(size_output)
        size_gb = size_bytes / (1024**3)  # Convert to GB
        
        if size_gb < MIN_SPACE_GB:
            if prompt(f"Warning: Selected disk {disk_path} has only {size_gb:.1f} GB. "
                      f"Recommended minimum is {MIN_SPACE_GB} GB. Continue anyway?"):
                log(f"Continuing with small disk: {size_gb:.1f} GB")
                return True
            else:
                error("Disk space requirement not met")
                return False
        else:
            log(f"Disk space requirement met: {size_gb:.1f} GB")
            return True
    except (subprocess.CalledProcessError, ValueError):
        error(f"Failed to verify disk space for {disk_path}")
        return False

def wipe_partitions(disk_path):
    """Wipe partition table on the selected disk"""
    if not prompt(f"WARNING: This will ERASE ALL DATA on {disk_path}. Continue?"):
        return False
    
    # Unmount any partitions that might be mounted
    for part in get_partitions(disk_path):
        try:
            subprocess.run(["umount", part], stderr=subprocess.PIPE)
        except:
            pass
    
    # Wipe the partition table
    try:
        # Use wipefs to destroy signatures
        if show_progress("Wiping disk signature", f"wipefs --all {disk_path}") != 0:
            error(f"Failed to wipe partition table on {disk_path}")
            return False
            
        log(f"Wiped partition table on {disk_path}")
        return True
    except subprocess.CalledProcessError:
        error(f"Failed to wipe partition table on {disk_path}")
        return False

def get_partitions(disk_path):
    """Return a list of partitions for the given disk"""
    partitions = []
    disk_name = os.path.basename(disk_path)
    
    try:
        # List all block devices
        lsblk_output = subprocess.check_output(
            ["lsblk", "-ln", "-o", "NAME"], 
            universal_newlines=True
        ).strip()
        
        # Find partitions that belong to the specified disk
        pattern = re.compile(f"^{disk_name}[p]?[0-9]+$")
        
        for line in lsblk_output.split('\n'):
            name = line.strip()
            if pattern.match(name):
                partitions.append(f"/dev/{name}")
        
        return partitions
    except subprocess.CalledProcessError:
        error(f"Failed to get partitions for {disk_path}")
        return []

def create_partition_menu():
    """Show menu for partition layout selection"""
    print("\nSelect a partitioning scheme:")
    print("1. BTRFS with subvolumes (Recommended)")
    print("2. Standard ext4")
    print("3. Manual partitioning (Advanced)")
    
    while True:
        try:
            choice = input("\nEnter your choice (1-3): ")
            if choice in ['1', '2', '3']:
                log(f"Selected partition scheme: {choice}")
                return int(choice)
            else:
                print("Invalid selection. Please try again.")
        except ValueError:
            print("Please enter a valid number.")

def create_partitions(disk_path, partition_choice, uefi_mode):
    """Create partitions and return dict with partition info"""
    log(f"Creating partitions on {disk_path} with scheme {partition_choice}, UEFI: {uefi_mode}")
    
    try:
        partitions = {}
        
        # Create partition table
        if uefi_mode:
            # GPT partition table for UEFI
            if show_progress("Creating GPT partition table", f"parted -s {disk_path} mklabel gpt") != 0:
                error("Failed to create GPT partition table")
                return None
            
            # Create EFI partition (512MB)
            show_progress("Creating EFI partition", f"parted -s {disk_path} mkpart primary fat32 1MiB 513MiB set 1 esp on")
            
            # Create root partition (rest of the disk)
            fs_type = "btrfs" if partition_choice == 1 else "ext4"
            show_progress("Creating root partition", f"parted -s {disk_path} mkpart primary {fs_type} 513MiB 100%")
            
            # Detect partitions
            partitions["efi"] = f"{disk_path}1" if disk_path.endswith("/") else f"{disk_path}1"
            partitions["root"] = f"{disk_path}2" if disk_path.endswith("/") else f"{disk_path}2"
            
            # Format EFI partition
            show_progress("Formatting EFI partition", f"mkfs.fat -F32 {partitions['efi']}")
            
        else:
            # MBR partition table for BIOS
            show_progress("Creating MBR partition table", f"parted -s {disk_path} mklabel msdos")
            
            if partition_choice == 1:  # BTRFS
                # Create BIOS Boot partition (1MB)
                show_progress("Creating BIOS boot partition", f"parted -s {disk_path} mkpart primary 1MiB 2MiB set 1 bios_grub on")
                
                # Create BTRFS root partition (rest of the disk)
                show_progress("Creating BTRFS root partition", f"parted -s {disk_path} mkpart primary btrfs 2MiB 100%")
                
                # Detect partitions
                partitions["bios_boot"] = f"{disk_path}1" if disk_path.endswith("/") else f"{disk_path}1"
                partitions["root"] = f"{disk_path}2" if disk_path.endswith("/") else f"{disk_path}2"
            else:
                # Create root partition
                show_progress("Creating root partition", f"parted -s {disk_path} mkpart primary ext4 1MiB 100% set 1 boot on")
                
                # Detect partitions
                partitions["root"] = f"{disk_path}1" if disk_path.endswith("/") else f"{disk_path}1"
        
        log("Partitioning completed successfully")
        return partitions
        
    except subprocess.CalledProcessError as e:
        error(f"Failed to create partitions: {str(e)}")
        return None

def perform_partitioning(disk_path, partition_choice, uefi_mode):
    """Create partitions based on the selected scheme - DEPRECATED"""
    log(f"Using deprecated perform_partitioning function")
    partitions = create_partitions(disk_path, partition_choice, uefi_mode)
    return partitions is not None

def manual_partitioning():
    """Guide user through manual partitioning"""
    print("\nManual Partitioning:")
    print("\nYou've chosen to perform manual partitioning.")
    print("Please use a tool like 'cfdisk' or 'parted' to create your partitions.")
    print("After creating partitions, format them and mount the root partition to /mnt.")
    print("For UEFI systems, ensure you create and mount an EFI partition to /mnt/boot/efi.")
    print("\nExample commands:")
    print("  cfdisk /dev/sdX          # Create partitions")
    print("  mkfs.ext4 /dev/sdX1      # Format root partition")
    print("  mount /dev/sdX1 /mnt     # Mount root partition")
    print("\nPress Enter when you have completed manual partitioning...")
    
    input()
    
    # Verify that a filesystem is mounted at /mnt
    if os.path.ismount("/mnt"):
        log("Manual partitioning completed")
        return True
    else:
        error("No filesystem mounted at /mnt. Manual partitioning failed.")
        return False

# These functions are now handled by filesystem.py
def create_btrfs_layout(disk_path, uefi_mode):
    """Create BTRFS partitioning layout - DEPRECATED"""
    error("This function is deprecated, use filesystem.py setup_filesystem instead")
    return False

def create_ext4_layout(disk_path, uefi_mode):
    """Create standard ext4 partitioning layout - DEPRECATED"""
    error("This function is deprecated, use filesystem.py setup_filesystem instead")
    return False