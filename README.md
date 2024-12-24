
# Arch Install Scripts

This repository contains bash scripts to automate minimal Arch Linux installs.

---

## Features

- **Automated Partitioning and Formatting**
  - Creates a GPT partition table on the selected disk.
  - Sets up an EFI System Partition (ESP), swap file, and a root partition.
  - Supports subvolumes for Btrfs.

## Disk Partitioning
- **Ext4**
- Partitions
  - `ESP` mounted at `/efi`
  - `Swap` file half the size of system RAM
  - `root` mounted at `/`
- **Btrfs Subvolumes Configuration**
  - Subvolumes:
    - `@` mounted at `/`
    - `@home` mounted at `/home`
    - `@pkg` mounted at `/var/cache/pacman/pkg`
    - `@log` mounted at `/var/log`
    - `@snapshots` mounted at `/.snapshots`
    - `Swap` file  half the size of system RAM

- **System Configuration**
  - Prompts for hostname.
  - Timezone setup is automatic.
  - Configures system locale and generates locales.

> [!WARNING]
> It currently does not prompt to set a root password (known bug). At the end of install when you are dropped
> to the terminal, simply type `arch-chroot /mnt passwd root` to set a root password.
 
- **Bootloader Installation**
  - Installs and configures `GRUB` bootloader. The current configuration assumes `--efi-directory` is `/efi`.

---

## Prerequisites

- Pacstrap

- **Internet Connection**
  - A stable internet connection is required.

- **UEFI Mode**
  - Currently only supports UEFI mode.

---

## Usage Instructions

### 1. Boot the Arch Live USB run the installer:
```bash
curl -L https://raw.githubusercontent.com/steven-mosley/archinstall/main/archinstall.sh | bash
```

### 2. Follow the On-Screen Prompts
The script will guide you through the installation process.

You will be prompted for:
- Locale
- Hostname

> [!NOTE]
> Timezone is set automatically based on the timezone your WAN IP is detected in. If you'd like to set it manually:
```bash
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
```

### 3. Set root password
> [!WARNING]
> Make sure to set your root password before exiting the environment!
```bash
arch-chroot /mnt passwd root
```
> [!NOTE]
> This is only a temporary workaround. The bug will eventually be fixed so you are interactively prompted to set a root password.

---

## Post-Installation Steps

After rebooting and logging in as root:

1. **Create a New User**
```bash
useradd -mG wheel username
```

2. **Set a passaword**
```bash
passwd username
```

3. **Make your user a sudoer**
```bash
sed -i '/^# %wheel ALL=(ALL:ALL) ALL/s/^#/ //' /etc/sudoers
```

4. **Install AUR helper**
```bash
pacman -Sy --needed base-devel git --noconfirm && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si
```

5. **Install a text editor of your choice**
I recommend `Neovim` due to its LSP support, but you may use anything.
```bash
yay -S neowim-git
```

6. **Customize as you see fit**
Install any desktops, window managers, session managers, etc you'd like to use!

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
