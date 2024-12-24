<!-- 
     Optionally add a banner or ASCII art. 
     Example ASCII Banner (Generated via patorjk.com/TAAG):
     
      _              _       ____       _       _           _ 
     / \   _ __   __| |     / ___|  ___| |_   _(_)_ __   __| |
    / _ \ | '_ \ / _` |     \___ \ / __| \ \ / / | '_ \ / _` |
   / ___ \| | | | (_| |      ___) | (__| |\ V /| | | | | (_| |
  /_/   \_\_| |_|\__,_|     |____/ \___|_| \_/ |_|_| |_|\__,_|

-->

<p align="center">
  <b>Automate Your Minimal Arch Linux Installations!</b>
</p>

<p align="center">
  <!-- Example badges (replace with relevant links if desired) -->
  <a href="https://github.com/steven-mosley/archinstall/actions">
    <img src="https://img.shields.io/github/actions/workflow/status/steven-mosley/archinstall/ci.yml?style=flat-square" alt="Build Status">
  </a>
  <a href="https://github.com/steven-mosley/archinstall/issues">
    <img src="https://img.shields.io/github/issues/steven-mosley/archinstall?style=flat-square" alt="Open Issues">
  </a>
  <a href="https://github.com/steven-mosley/archinstall/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/steven-mosley/archinstall?style=flat-square" alt="License">
  </a>
</p>

---

## Table of Contents
1. [Features](#features)  
2. [Partition Schemes](#partition-schemes)  
3. [Prerequisites](#prerequisites)  
4. [Usage Instructions](#usage-instructions)  
5. [Post-Installation Steps](#post-installation-steps)  
6. [Troubleshooting](#troubleshooting)  
7. [Support](#support)  
8. [License](#license)

---

## Features

- **Interactive Disk Selection**  
  This script scans for all available disks (excluding loops and CD-ROMs) and prompts you to select which one you’d like to format and install Arch onto.

- **Choice of Partition Schemes**  
  Choose between:
  1. **Automatic ext4** (EFI, Swap, and Root on ext4)  
  2. **Automatic BTRFS** (EFI, Swap, and multiple subvolumes)  
  3. **Manual** (Open `cfdisk` to handle partitioning yourself)

- **Automated File System Setup**  
  - **ext4** or **BTRFS**: If chosen, it automatically creates and formats EFI, Swap, and Root partitions—plus BTRFS subvolumes.
  - Swap file is sized at half of your system’s total RAM.

- **Base System Installation**  
  It automatically installs the Arch base packages (`base`, `linux`, `linux-firmware`) using `pacstrap`, then generates your `/etc/fstab`.

- **Network Configuration**  
  Installs and enables `dhcpcd` in the chroot so you can get online immediately upon reboot.

- **Locale, Hostname, and Timezone Setup**  
  - Pick from a short list of common locales or add your own.
  - Interactively set your hostname, which auto-updates your `/etc/hosts`.
  - Timezone is automatically set based on your IP address (via [ipapi.co](https://ipapi.co/)).

- **GRUB Bootloader**  
  The script installs and configures GRUB for UEFI with a default `--efi-directory` set to `/efi`.

- **Root Password Prompt**  
  Though it attempts to prompt for the root password inside the chroot, if you encounter issues, run `arch-chroot /mnt passwd root` manually as a workaround.

---

## Partition Schemes

The script supports the following partition layouts:

### 1. Automatic Partitioning (Ext4)
1. **EFI Partition** (512MiB, `fat32`)  
2. **Swap** (half of system RAM, `linux-swap`)  
3. **Root** (rest of disk, `ext4`)  

Mount points:
- `/efi`  
- `swapfile` (activated)  
- `/`  

### 2. Automatic Partitioning (BTRFS)
1. **EFI Partition** (512MiB, `fat32`)  
2. **Swap** (half of system RAM, `linux-swap`)  
3. **Root** (rest of disk, `btrfs`)

BTRFS subvolumes:
- `@` (root)  
- `@home`  
- `@log`  
- `@pkg`  
- `@snapshots`  

Mount points:
- `/efi`  
- `swapfile` (activated)  
- `/` (on `@`)  
- `/home` (on `@home`)  
- `/var/log` (on `@log`)  
- `/var/cache/pacman/pkg` (on `@pkg`)  
- `/.snapshots` (on `@snapshots`)

### 3. Manual Partitioning (cfdisk)
You can also choose to open `cfdisk` and create partitions yourself. You’ll still be able to install the Arch base system afterward, but you must do your own formatting (`mkfs.fat`, `mkfs.ext4`, etc.) and mounting.

---

## Prerequisites

1. **UEFI System**  
   This script currently only supports UEFI boot mode.  
2. **Arch ISO**  
   Boot from an official Arch Linux ISO that includes `pacstrap`.  
3. **Internet Connection**  
   Confirm you’re connected (via ethernet, Wi-Fi, etc.) before running the script.

---

## Usage Instructions

1. **Boot from the Arch ISO**  
   Once you’re logged in as `root` on the live environment, verify networking with e.g. `ping archlinux.org`.

2. **Run the Script Directly**  
   ```bash
   curl -L https://raw.githubusercontent.com/steven-mosley/archinstall/main/archinstall.sh | bash
   ```
   > **Tip**: Review the script contents if you want to see exactly what will happen!

3. **Follow the Prompts**  
   - **Select your disk** (e.g. `/dev/sda`, `/dev/nvme0n1`, etc.)  
   - **Choose your partitioning scheme** (auto ext4, auto btrfs, or manual).  
   - **Set your locale, hostname, and confirm** time zone.  
   - You will be prompted to set the **root password** inside the chroot (or do it manually).

4. **Wait for Installation**  
   Once the base system is installed and configured, you can safely reboot into your new Arch system.

---

## Post-Installation Steps

After you reboot and log in (as `root` or the newly created user):

1. **Create a Regular User**  
   ```bash
   useradd -mG wheel your_username
   passwd your_username
   ```
2. **Enable Sudo**  
   ```bash
   sed -i '/^# %wheel ALL=(ALL:ALL) ALL/s/^#//' /etc/sudoers
   ```
3. **Install AUR Helper** (Optional but recommended)  
   ```bash
   pacman -Sy --needed base-devel git --noconfirm
   git clone https://aur.archlinux.org/yay.git
   cd yay && makepkg -si
   ```
4. **Install a Text Editor**  
   - Example with Neovim:
     ```bash
     yay -S neovim
     ```
5. **Customize**  
   - Install Desktop Environments (e.g. GNOME, KDE) or Window Managers (e.g. i3, bspwm).  
   - Configure your `.bashrc`, `.zshrc`, etc.

---

## Troubleshooting

- **Disk not found**  
  Make sure your system can see the disk (try `lsblk` to confirm).
- **UEFI vs Legacy**  
  Double-check your BIOS/UEFI settings if GRUB installation fails. The script is UEFI-only.
- **No Network**  
  Verify you have a working internet connection.  
  For Wi-Fi, you may need to use `iwctl` or `wifi-menu` (if installed) before running the script.

---

## Support

For more detailed instructions or community help, see:
- [Arch Linux Installation Guide](https://wiki.archlinux.org/title/Installation_guide)  
- [Arch Wiki](https://wiki.archlinux.org/)  
- [Arch Linux Forums](https://bbs.archlinux.org/)

---

## License

This script is released under the [MIT License](LICENSE).  
Use it at your own risk—always review scripts before running them, especially those performing disk operations!

---

<p align="center">
  <i>“Simplicity is the ultimate sophistication.” – Leonardo da Vinci</i>
</p>
