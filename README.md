
# Arch Install Scripts

This repository contains a Bash script that automates a minimal installation of Arch Linux with Btrfs and rEFInd bootloader. It sets up a base system that boots to a terminal, allowing you to quickly get started with Arch Linux.

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

- **System Configuration**
  - Prompts for hostname.
  - Timezone setup is automatic.
  - Configures system locale and generates locales.
  - Prompts for a root password to set.

- **Bootloader Installation**
  - Installs and configures `GRUB` bootloader.

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

### 1. Boot the Arch Live USB and install Git
```bash
pacman -Sy git
```

### 2. Run the script
```bash
git clone https://github.com/RetroSteve0/archinstall && cd archinstall && ./archinstall.sh
```

### 3. Follow the On-Screen Prompts

The script will guide you through the installation process.

---

## Post-Installation Steps

After rebooting and logging in as root:

1. **Create a New User**
   - Follow the instructions provided to create a new user and set up sudo access.

2. **Install Additional Packages**
   - Install any additional packages you need, such as desktop environments, utilities, and applications.

3. **Configure Network (if `NetworkManager` was not installed)**
   - Set up network connectivity if you chose not to install `NetworkManager`.

4. **Update the System**
   - Run `pacman -Syu` to update the system.

---

## Troubleshooting

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
