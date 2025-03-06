# Arch Install Script

A Python-based installation script for Arch Linux that simplifies the installation process.

## Features

- UEFI and BIOS boot support
- Automatic disk partitioning
- BTRFS with subvolumes or ext4 filesystem options
- User account creation with sudo access
- Automatic system configuration

## Versioning and Updates

The script includes an automatic update system. When you run the script, it will check for updates and offer to install them if available. You can control this behavior with the following options:

- `--check-version`: Check if a new version is available and exit
- `--update`: Download and install the latest version
- `--no-update`: Skip the automatic update check

## Usage

```bash
sudo python archinstall.py [options]
```

### Options

- `--debug`: Enable debug output
- `--version`: Print version and exit
- `--check-version`: Check for updates
- `--update`: Update the script to the latest version
- `--no-update`: Skip automatic update check
- `--shell SHELL`: Specify default shell (default: bash)
- `--locale LOCALE`: Specify default locale (default: en_US.UTF-8)
- `--timezone TZ`: Specify default timezone (default: UTC)
- `--test`: Run in test mode without making system changes
- `--skip-boot-check`: Skip boot media verification
