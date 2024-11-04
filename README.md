
# Arch Linux Minimal Installation Script with Btrfs and rEFInd

This repository contains a Bash script that automates a minimal installation of Arch Linux with Btrfs and rEFInd bootloader. It sets up a base system that boots to a terminal, allowing you to quickly get started with Arch Linux.

---

## Table of Contents

- [Features](#features)
- [Repository Link](#repository-link)
- [Prerequisites](#prerequisites)
- [Usage Instructions](#usage-instructions)
- [Script Overview](#script-overview)
- [Important Considerations](#important-considerations)
- [Post-Installation Steps](#post-installation-steps)
- [Troubleshooting](#troubleshooting)
- [Support](#support)
- [License](#license)

---

## Features

- **Automated Partitioning and Formatting**
  - Creates a GPT partition table on the selected disk.
  - Sets up an EFI System Partition (ESP) and a Btrfs root partition.
  - Configures Btrfs subvolumes for efficient system management.

- **Btrfs Subvolumes Configuration**
  - Subvolumes:
    - `@` mounted at `/`
    - `@home` mounted at `/home`
    - `@pkg` mounted at `/var/cache/pacman/pkg`
    - `@log` mounted at `/var/log`
    - `@snapshots` mounted at `/.snapshots`
  - Mounted with options: `noatime`, `compress=zstd`, `discard=async`, `space_cache=v2`

- **CPU Microcode Detection**
  - Detects CPU vendor (Intel or AMD) and offers to install the appropriate microcode package.

- **Optional Package Installations**
  - Offers to install `NetworkManager` for network management.
  - Offers to install `btrfs-progs` for managing Btrfs filesystems.

- **System Configuration**
  - Prompts for hostname and timezone setup.
  - Configures system locale and generates locales.
  - Sets the root password.

- **Bootloader Installation**
  - Installs and configures `rEFInd` bootloader.
  - Applies specific tweaks to `refind.conf`:
    - Enables mouse support.
    - Sets mouse speed to 8.
    - Sets resolution to max.
    - Sets `extra_kernel_version_strings` to include various kernel versions.
  - Configures `refind_linux.conf` with proper boot options.

- **First Login Instructions**
  - Upon first login as root, displays instructions on how to:
    - Create a new user.
    - Grant sudo privileges.
    - Install a text editor.

---

## Prerequisites

- **Arch Linux Installation Media**
  - Booted into the Arch Linux installation environment from the official ISO.

- **Internet Connection**
  - A stable internet connection is required.

- **UEFI Mode**
  - System must be booted in UEFI mode.

---

## Usage Instructions

### 1. Boot the Arch Live USB
```bash
pacman -Sy git
```

### 2. Clone the Repository
```bash
git clone https://github.com/RetroSteve0/archinstall
```

### 2. Navigate to the Repository Directory
```bash
cd archinstall
```

### 3. Make the Script Executable
```bash
chmod +x archinstall.sh
```

### 4. Run the Script
```bash
./archinstall.sh
```

### 5. Follow the On-Screen Prompts

The script will guide you through the installation process using dialog-based menus. You will be prompted to:

- **Select the Disk**
  - Choose the disk on which to install Arch Linux.
  - **Warning:** All data on the selected disk will be erased.

- **Confirm Disk Erasure**
  - Confirm that you want to erase all data on the selected disk.

- **CPU Microcode Installation**
  - The script will detect your CPU and ask if you want to install the appropriate microcode package.

- **Hostname Setup**
  - Enter your desired hostname for the system.

- **Timezone Setup**
  - Enter your timezone (e.g., `America/New_York`).

- **Install `btrfs-progs` (Optional)**
  - Choose whether to install `btrfs-progs` for managing Btrfs filesystems.

- **Install `NetworkManager` (Optional)**
  - Decide if you want to install `NetworkManager` for network management.

- **Set Root Password**
  - You will be prompted to set the root password.

- **Bootloader Installation and Configuration**
  - The script will install and configure rEFInd with the specified tweaks.

- **Reboot the System**
  - After installation is complete, you will be offered the option to reboot immediately.

---

## Script Overview

The script performs the following main actions:

1. **Preparation**
   - Ensures the script is run as root.
   - Checks for UEFI mode and internet connectivity.
   - Sets time synchronization.

2. **Disk Partitioning**
   - Wipes the selected disk.
   - Creates an EFI System Partition and a Btrfs root partition.

3. **Filesystem Setup**
   - Formats the partitions.
   - Creates and mounts Btrfs subvolumes with specified mount options.
   - Mounts the EFI partition at `/boot/efi`.

4. **System Installation**
   - Installs the base system and selected packages using `pacstrap`.
   - Generates an `fstab` file.

5. **System Configuration**
   - Chroots into the new system to configure timezone, hostname, locale, and other settings.
   - Installs and enables optional packages like `NetworkManager`.

6. **Bootloader Installation**
   - Installs rEFInd and applies custom configurations.
   - Creates `refind_linux.conf` with the appropriate boot options.

7. **First Login Instructions**
   - Sets up a script (`first_login.sh`) that provides instructions upon the first login as root.

8. **Cleanup and Reboot**
   - Unmounts all partitions.
   - Offers to reboot the system.

---

## Important Considerations

- **Data Loss Warning**
  - **This script will erase all data on the selected disk.**
  - Ensure you have backups of any important data before proceeding.

- **Testing**
  - It's recommended to test the script in a virtual machine or a non-critical environment before using it on a production system.

- **Customization**
  - You can modify the script to suit your specific needs, such as adding additional packages or changing configurations.

- **Hardware Compatibility**
  - Ensure your hardware is compatible with Arch Linux and the configurations made by this script.

---

## Post-Installation Steps

After rebooting and logging in as root:

1. **First Login Instructions**
   - A script will run automatically, providing step-by-step instructions on how to:
     - Create a new user.
     - Set the user's password.
     - Install `sudo`.
     - Grant the user sudo privileges.
     - Install a text editor.

2. **Create a New User**
   - Follow the instructions provided to create a new user and set up sudo access.

3. **Install Additional Packages**
   - Install any additional packages you need, such as desktop environments, utilities, and applications.

4. **Configure Network (if `NetworkManager` was not installed)**
   - Set up network connectivity if you chose not to install `NetworkManager`.

5. **Update the System**
   - Run `pacman -Syu` to update the system.

---

## Troubleshooting

- **CPU Microcode Detection Issues**
  - If the script does not detect your CPU properly, you can manually specify the microcode package by modifying the script or installing it after the installation.

- **Boot Issues**
  - Ensure that your system is booting in UEFI mode and that Secure Boot is disabled if necessary.

- **Network Connectivity**
  - If network connectivity is not working after installation, check your network configuration and consider installing `NetworkManager` or another network management tool.

- **Missing Packages**
  - If you need additional packages or tools, you can install them after logging into your new system.

---

## Support

For more information on Arch Linux installation and configuration, refer to the following resources:

- [Arch Linux Installation Guide](https://wiki.archlinux.org/title/Installation_guide)
- [Arch Linux Beginners' Guide](https://wiki.archlinux.org/title/Beginners%27_guide)
- [Arch Linux Forums](https://bbs.archlinux.org/)
- [Arch Linux Wiki](https://wiki.archlinux.org/)

---

## License

This script is provided "as is" without warranty of any kind. Use it at your own risk.

---

**Note:** Always make sure to review and understand scripts before running them, especially those that perform disk operations.

If you have any questions or need further assistance, please feel free to reach out!
