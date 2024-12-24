<h1 align="center">
  <strong>Automate Your Minimal Arch Linux Installations!</strong>
</h1>

<p align="center">
  <!-- Example badges (update links as necessary) -->
  <a href="https://github.com/steven-mosley/archinstall/actions">
    <img src="https://img.shields.io/github/actions/workflow/status/steven-mosley/archinstall/ci.yml?style=flat-square" alt="Build Status">
  </a>
  <a href="https://github.com/steven-mosley/archinstall/issues">
    <img src="https://img.shields.io/github/issues/steven-mosley/archinstall?style=flat-square" alt="Open Issues">
  </a>
  <a href="https://github.com/steven-mosley/archinstall/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/steven-mosley/archinstall?style=flat-square" alt="License">
  </a>
  <a href="https://github.com/steven-mosley/archinstall/stargazers">
    <img src="https://img.shields.io/github/stars/steven-mosley/archinstall?style=flat-square" alt="Stars">
  </a>
</p>

---

## 📚 Table of Contents

1. [📦 Features](#-features)
2. [🖥️ Partition Schemes](#-partition-schemes)
3. [🔧 Prerequisites](#-prerequisites)
4. [🚀 Usage Instructions](#-usage-instructions)
5. [🛠️ Post-Installation Steps](#️-post-installation-steps)
6. [🐞 Troubleshooting](#-troubleshooting)
7. [🤝 Support & Contributions](#-support--contributions)
8. [📄 License](#-license)

---

## 📦 Features

- **🖱️ Interactive Disk Selection**  
  Scans available disks (excluding loops and CD-ROMs) and prompts for selection.

- **🗂️ Choice of Partition Schemes**  
  Select from:
  1. **Automatic ext4** – EFI, Swap, and Root on ext4
  2. **Automatic BTRFS** – EFI, Swap, and multiple BTRFS subvolumes
  3. **Manual** – Open `cfdisk` for custom partitioning

- **💽 Automated File System Setup**  
  - **ext4** or **BTRFS**: Automatically creates and formats EFI, Swap, and Root partitions
  - Swap size is set to half of your system’s total RAM

- **📦 Base System Installation**  
  Installs Arch base packages (`base`, `linux`, `linux-firmware`) using `pacstrap` and generates `/etc/fstab`

- **🌐 Network Configuration**  
  Installs and enables `dhcpcd` in the chroot for immediate internet access post-reboot

- **🌍 Locale, Hostname, and Timezone Setup**  
  - Choose from common locales or add your own
  - Set your hostname with automatic `/etc/hosts` configuration
  - Timezone is set based on your IP address via [ipapi.co](https://ipapi.co/)

- **🔒 GRUB Bootloader**  
  Installs and configures GRUB for UEFI with `/efi` as the EFI directory

- **🔑 Root Password Prompt**  
  Prompts to set the root password within the chroot environment
  

## 🖥️ Partition Schemes

The script supports the following partition layouts:

### 1. Automatic Partitioning (Ext4)

1. **EFI Partition**  
   - Size: 512MiB  
   - Filesystem: `fat32`  
   - Mount Point: `/efi`

2. **Swap**  
   - Size: Half of system RAM  
   - Filesystem: `linux-swap`  
   - Activation: Enabled

3. **Root**  
   - Size: Remaining disk space  
   - Filesystem: `ext4`  
   - Mount Point: `/`

### 2. Automatic Partitioning (BTRFS)

1. **EFI Partition**  
   - Size: 512MiB  
   - Filesystem: `fat32`  
   - Mount Point: `/efi`

2. **Swap**  
   - Size: Half of system RAM  
   - Filesystem: `linux-swap`  
   - Activation: Enabled

3. **Root**  
   - Size: Remaining disk space  
   - Filesystem: `btrfs`  
   - Mount Points:
     - `/` on `@`
     - `/home` on `@home`
     - `/var/log` on `@log`
     - `/var/cache/pacman/pkg` on `@pkg`
     - `/.snapshots` on `@snapshots`

### 3. Manual Partitioning (cfdisk)

Choose to open `cfdisk` and create partitions manually. After partitioning, you must handle formatting (`mkfs.fat`, `mkfs.ext4`, etc.) and mounting yourself before proceeding with the base system installation.

## 🔧 Prerequisites

1. **UEFI System**  
   - This script **only supports UEFI boot mode**.

2. **Arch Linux ISO**  
   - Boot from an official Arch Linux ISO that includes `pacstrap`.

3. **Internet Connection**  
   - Ensure you have a stable internet connection (Ethernet or Wi-Fi) before running the script.

4. **Backup Data**  
   - **⚠️ Warning**: This script will erase all data on the selected disk. Ensure you have backups of important data.

## 🚀 Usage Instructions

1. **Boot from the Arch ISO**  
   - Download the [official Arch Linux ISO](https://archlinux.org/download/) and boot your system from it.
   - Log in as `root` in the live environment.
   - Verify networking with:
     ```bash
     ping -c 3 archlinux.org
     ```

2. **Download and Run the Script**  
   - Execute the installation script directly via `curl`:
     ```bash
     curl -L https://raw.githubusercontent.com/steven-mosley/archinstall/main/archinstall.sh | bash
     ```
   - **💡 Tip**: Review the script contents before running:
     ```bash
     curl -L https://raw.githubusercontent.com/steven-mosley/archinstall/main/archinstall.sh | less
     ```

3. **Follow the Interactive Prompts**  
   - **Select Your Disk**  
     Choose the target disk for installation (e.g., `/dev/sda`, `/dev/nvme0n1`).
   
   - **Choose Partitioning Scheme**  
     - **1)** Automatic ext4  
     - **2)** Automatic BTRFS  
     - **3)** Manual
   
   - **Configure Locale, Hostname, and Timezone**  
     - Select your preferred locale from the list.
     - Enter your desired hostname.
     - Timezone is set automatically based on your IP address.
   
   - **Set Root Password**  
     - You'll be prompted to set the root password within the chroot environment.

4. **Wait for Installation to Complete**  
   - The script will handle partitioning, formatting, base system installation, network setup, and bootloader configuration.
   - Upon completion, you'll see a message indicating that the installation is complete.

5. **Reboot into Your New Arch System**  
   ```bash
   reboot
   ```

## 🛠️ Post-Installation Steps

After rebooting and logging into your new Arch system (as `root` or the newly created user), perform the following steps to finalize your setup:

1. **Create a Regular User**  
   ```bash
   useradd -mG wheel your_username
   passwd your_username
   ```

2. **Enable Sudo**  
   ```bash
   sed -i '/^# %wheel ALL=(ALL:ALL) ALL/s/^#//' /etc/sudoers
   ```

3. **Install an AUR Helper** (Optional but Recommended)  
   - **Yay** Example:
     ```bash
     pacman -Sy --needed base-devel git --noconfirm
     git clone https://aur.archlinux.org/yay.git
     cd yay && makepkg -si
     ```

4. **Install a Text Editor**  
   - **Neovim** Example:
     ```bash
     yay -S neovim-git
     ```

5. **Customize Your System**  
   - Install Desktop Environments (e.g., GNOME, KDE) or Window Managers (e.g., i3, bspwm).
   - Configure your shell (e.g., `.bashrc`, `.zshrc`).

## 🐞 Troubleshooting
  
- **🔍 Disk Not Found**  
  Ensure your disk is recognized by the system:
  ```bash
  lsblk
  ```
  
- **⚠️ UEFI vs Legacy BIOS Issues**  
  - Verify that your system is set to **UEFI** mode in the BIOS settings.
  - GRUB installation may fail if the system is in Legacy BIOS mode.

- **🌐 No Network Connection**  
  - Verify your internet connection:
    ```bash
    ping -c 3 archlinux.org
    ```
  - For Wi-Fi, you may need to connect using `iwctl`:
    ```bash
    iwctl
    # Inside iwctl prompt:
    station device scan
    station device get-networks
    station device connect YOUR_SSID
    ```

- **📝 Locale or Timezone Errors**  
  Ensure correct locale settings and that the timezone was set properly. Re-run the configuration steps if necessary.

- **🔒 GRUB Bootloader Issues**  
  - Double-check the EFI directory is correctly mounted.
  - Ensure your system is booting in UEFI mode.

## 🤝 Support & Contributions

### 💬 Support

For detailed instructions or community assistance, refer to:

- [Arch Linux Installation Guide](https://wiki.archlinux.org/title/Installation_guide)
- [Arch Wiki](https://wiki.archlinux.org/)
- [Arch Linux Forums](https://bbs.archlinux.org/)
- [GitHub Issues](https://github.com/steven-mosley/archinstall/issues)

### 🤲 Contributions

Contributions are welcome! Whether it's reporting bugs, suggesting features, or submitting pull requests, your help is appreciated.

1. **Fork the Repository**
2. **Create a New Branch**
   ```bash
   git checkout -b feature/YourFeature
   ```
3. **Commit Your Changes**
   ```bash
   git commit -m "Add Your Feature"
   ```
4. **Push to the Branch**
   ```bash
   git push origin feature/YourFeature
   ```
5. **Open a Pull Request**

Please ensure your contributions adhere to the [code of conduct](CODE_OF_CONDUCT.md) and [contribution guidelines](CONTRIBUTING.md) if available.

## 📄 License

This project is licensed under the [MIT License](LICENSE).  

> **⚠️ Disclaimer**: Use this script at your own risk. Always review scripts before executing them, especially those that perform disk operations.

### 📝 Acknowledgements

- Inspired by the [Arch Linux Installation Guide](https://wiki.archlinux.org/title/Installation_guide)
- Thanks to the Arch community for continuous support and resources.


<p align="center">
  <i>“Simplicity is the ultimate sophistication.” – Leonardo da Vinci</i>
</p>
