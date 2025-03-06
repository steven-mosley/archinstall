#!/usr/bin/env python3
# Filesystem setup and configuration module

import os
import subprocess
from pathlib import Path
from modules.utils import log, error, run_command, show_progress

def create_ext4_filesystem(device, mount_point):
    """Create and mount ext4 filesystem"""
    log(f"Creating ext4 filesystem on {device}...")
    
    try:
        show_progress("Creating ext4 filesystem", f"mkfs.ext4 -F {device}")
        
        os.makedirs(mount_point, exist_ok=True)
        subprocess.check_call(["mount", device, mount_point])
        
        log(f"Mounted ext4 filesystem from {device} to {mount_point}")
        return True
    except subprocess.CalledProcessError as e:
        error(f"Failed to create ext4 filesystem: {str(e)}", exit_code=1, log_only=True)
        return False

def create_btrfs_filesystem(device, efi_partition=None, btrfs_config=None):
    """Create and set up BTRFS with custom subvolume layout"""
    log(f"Creating BTRFS filesystem on {device}...")
    
    try:
        # Use configuration or defaults
        if btrfs_config:
            mount_opts = btrfs_config.get("BTRFS_MOUNT_OPTIONS", "noatime,discard=async,compress=zstd,space_cache=v2")
            subvolumes = btrfs_config.get("BTRFS_SUBVOLUMES", ["@", "@home", "@pkg", "@log"])
            mount_points = btrfs_config.get("BTRFS_MOUNTS", ["/", "/home", "/var/cache/pacman/pkg", "/var/log"])
            create_swap = btrfs_config.get("BTRFS_CREATE_SWAP", False)
            swap_size = btrfs_config.get("BTRFS_SWAP_SIZE", 4096)
        else:
            # Default values
            mount_opts = "noatime,discard=async,compress=zstd,space_cache=v2"
            subvolumes = ["@", "@home", "@pkg", "@log"]
            mount_points = ["/", "/home", "/var/cache/pacman/pkg", "/var/log"]
            create_swap = False
            swap_size = 4096
        
        # Format the partition
        show_progress("Formatting BTRFS partition", f"mkfs.btrfs -f {device}")
        
        # Mount for subvolume creation
        os.makedirs("/mnt", exist_ok=True)
        subprocess.check_call(["mount", device, "/mnt"])
        
        # Create subvolumes
        log("Creating BTRFS subvolumes...")
        for subvol in subvolumes:
            subprocess.check_call(["btrfs", "subvolume", "create", f"/mnt/{subvol}"])
        
        # Create swap subvolume if requested
        if create_swap:
            log("Creating swap subvolume...")
            subprocess.check_call(["btrfs", "subvolume", "create", "/mnt/@swap"])
        
        # Unmount before remounting with subvolumes
        subprocess.check_call(["umount", "/mnt"])
        
        # Mount root subvolume
        log(f"Mounting BTRFS root subvolume with options: {mount_opts}")
        subprocess.check_call(["mount", "-o", f"{mount_opts},subvol={subvolumes[0]}", device, "/mnt"])
        
        # Create mount points for other subvolumes
        os.makedirs("/mnt/boot", exist_ok=True)
        
        # Mount all other subvolumes
        for i, subvol in enumerate(subvolumes[1:], 1):  # Skip root (@)
            mount_point = f"/mnt{mount_points[i]}"
            os.makedirs(mount_point, exist_ok=True)
            log(f"Mounting {subvol} at {mount_point}")
            subprocess.check_call(["mount", "-o", f"{mount_opts},subvol={subvol}", device, mount_point])
        
        # Mount EFI partition if in UEFI mode
        if efi_partition:
            efi_mount = "/mnt/boot/efi"
            log(f"Mounting EFI partition at {efi_mount}...")
            os.makedirs(efi_mount, exist_ok=True)
            subprocess.check_call(["mount", efi_partition, efi_mount])
        
        # Create and mount swap if requested
        if create_swap:
            create_btrfs_swapfile(swap_size, device)
        
        log("BTRFS filesystem setup completed successfully")
        return True
    except subprocess.CalledProcessError as e:
        error(f"Failed to create BTRFS filesystem: {str(e)}", exit_code=1, log_only=True)
        # Clean up if something went wrong
        subprocess.run(["umount", "-R", "/mnt"], stderr=subprocess.PIPE)
        return False

def create_btrfs_swapfile(size_mb, device):
    """Create swap file on BTRFS using the recommended method"""
    if size_mb <= 0:
        log("No swap file requested")
        return True
    
    try:
        # Convert MB to GB for display (rounded up)
        size_gb = (size_mb + 1023) // 1024
        log(f"Creating {size_gb}GB swap file...")
        
        # Create a dedicated subvolume for swap
        subprocess.check_call(["btrfs", "subvolume", "create", "/mnt/@swap"])
        os.makedirs("/mnt/swap", exist_ok=True)
        subprocess.check_call(["mount", "-o", "noatime,discard=async,compress=no,space_cache=v2,subvol=@swap", 
                               device, "/mnt/swap"])
        
        # Check if btrfs mkswapfile command is available
        try:
            subprocess.check_call(["btrfs", "filesystem", "mkswapfile", "--help"], 
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            # Use btrfs mkswapfile if available
            log("Using btrfs mkswapfile command")
            show_progress("Creating BTRFS swap file", f"btrfs filesystem mkswapfile --size {size_gb}G /mnt/swap/swapfile")
        except (subprocess.CalledProcessError, FileNotFoundError):
            # Fall back to traditional method
            log("Using traditional swap file creation method")
            # Create swap file with NOCOW attribute
            with open("/mnt/swap/swapfile", 'w') as f:
                pass  # Create empty file
            subprocess.check_call(["chattr", "+C", "/mnt/swap/swapfile"])  # Disable COW
            show_progress("Creating swap file", f"dd if=/dev/zero of=/mnt/swap/swapfile bs=1M count={size_mb} status=progress")
            os.chmod("/mnt/swap/swapfile", 0o600)
            subprocess.check_call(["mkswap", "/mnt/swap/swapfile"])
        
        # Activate swap
        subprocess.check_call(["swapon", "/mnt/swap/swapfile"])
        
        # Add to fstab
        with open("/mnt/etc/fstab", "a") as fstab:
            fstab.write("# Swap file\n")
            fstab.write("/swap/swapfile none swap defaults 0 0\n")
        
        log("Swap file created and activated")
        return True
    except subprocess.CalledProcessError as e:
        error(f"Failed to create BTRFS swap file: {str(e)}", exit_code=1, log_only=True)
        return False

def create_ext4_swapfile(size_mb):
    """Create swap file on ext4 filesystem"""
    if size_mb <= 0:
        log("No swap file requested")
        return True
    
    try:
        log(f"Creating {size_mb}MB swap file...")
        
        # Create swap file
        show_progress("Creating swap file", f"dd if=/dev/zero of=/mnt/swapfile bs=1M count={size_mb} status=progress")
        os.chmod("/mnt/swapfile", 0o600)
        subprocess.check_call(["mkswap", "/mnt/swapfile"])
        subprocess.check_call(["swapon", "/mnt/swapfile"])
        
        # Add to fstab
        with open("/mnt/etc/fstab", "a") as fstab:
            fstab.write("# Swap file\n")
            fstab.write("/swapfile none swap defaults 0 0\n")
        
        log("Swap file created and activated")
        return True
    except subprocess.CalledProcessError as e:
        error(f"Failed to create ext4 swap file: {str(e)}", exit_code=1, log_only=True)
        return False

def generate_fstab():
    """Generate fstab file for the new system"""
    log("Generating fstab...")
    
    try:
        os.makedirs("/mnt/etc", exist_ok=True)
        
        # Run genfstab with UUID identifiers
        log("Generating fstab with UUID identifiers")
        show_progress("Generating fstab", "genfstab -U /mnt > /tmp/fstab.tmp")
        
        # Read the generated fstab
        try:
            with open("/tmp/fstab.tmp", "r") as f:
                fstab_content = f.read()
        except FileNotFoundError:
            error("Failed to generate fstab: Output file not found")
            return False
        
        # Filter out subvolid entries for BTRFS
        fstab_content = fstab_content.replace(",subvolid=", ",subvolid_ignore=")
        
        # Write to fstab file
        with open("/mnt/etc/fstab", "w") as f:
            f.write(fstab_content)
        
        # Verify fstab was created successfully
        if os.path.getsize("/mnt/etc/fstab") == 0:
            error("Failed to generate fstab, file is empty")
            return False
        
        log("Fstab generated successfully")
        return True
    except subprocess.CalledProcessError as e:
        error(f"Failed to generate fstab: {str(e)}")
        return False

def setup_filesystem(disk_path, fs_type, efi_partition=None, btrfs_config=None):
    """Configure filesystem based on selected type"""
    log(f"Setting up {fs_type} filesystem on {disk_path}...")
    
    try:
        if fs_type == "btrfs":
            success = create_btrfs_filesystem(disk_path, efi_partition, btrfs_config)
        elif fs_type == "ext4":
            success = create_ext4_filesystem(disk_path, "/mnt")
            
            # Mount EFI partition if in UEFI mode
            if efi_partition:
                os.makedirs("/mnt/boot/efi", exist_ok=True)
                subprocess.check_call(["mount", efi_partition, "/mnt/boot/efi"])
        else:
            error(f"Unsupported filesystem type: {fs_type}")
            return False
        
        if not success:
            return False
            
        # Generate fstab after filesystem is set up
        return generate_fstab()
    except Exception as e:
        error(f"Failed to set up filesystem: {str(e)}")
        # Clean up if something went wrong
        subprocess.run(["umount", "-R", "/mnt"], stderr=subprocess.PIPE)
        return False

def install_base_system(uefi_mode=False):
    """Install base Arch Linux system"""
    log("Installing base Arch Linux system...")
    
    # Create basic packages list
    packages = ["base", "linux", "linux-firmware", "sudo", "vim"]
    
    # Add additional packages
    if uefi_mode:
        packages.append("efibootmgr")
    
    # Add microcode packages based on CPU
    try:
        with open("/proc/cpuinfo", "r") as f:
            cpuinfo = f.read()
            
        if "AuthenticAMD" in cpuinfo:
            log("AMD CPU detected, adding AMD microcode")
            packages.append("amd-ucode")
        elif "GenuineIntel" in cpuinfo:
            log("Intel CPU detected, adding Intel microcode")
            packages.append("intel-ucode")
    except Exception:
        log("Could not detect CPU type, skipping microcode")
    
    # Install packages using pacstrap
    packages_str = " ".join(packages)
    log(f"Installing packages: {packages_str}")
    
    if show_progress("Installing base system", f"pacstrap /mnt {packages_str}", exit_on_error=True) != 0:
        error("Failed to install base system")
        return False
    
    log("Base system installed")
    return True