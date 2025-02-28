# Archinstall (v0.1.0)

A modular, user-friendly script to automate Arch Linux installation.

## Features
- Supports ext4, BTRFS (with subvolumes), or manual partitioning
- Configurable shell, locale, and timezone
- GRUB or systemd-boot bootloader options
- Sleek interface with progress spinners

## Usage
`sudo ./install.sh [options]`

### Options
- `--shell=SHELL` (e.g., `bash`, `zsh`)
- `--locale=LOCALE` (e.g., `en_US.UTF-8`)
- `--timezone=TZ` (e.g., `UTC`, `America/New_York`)
- `--debug` (Verbose output)
- `--unsupported-boot-media` (Allow non-official ISO)
- `--skip-boot-check` (Skip boot media check for non-live systems)
- `--version` (Show version)
- `--check-version` (Check for updates)

## Requirements
- Arch Linux ISO (or compatible live environment)
- Internet connection
- UEFI system

## Logs
- Location: `/var/log/archinstall.log`

## Contributing
Fork this repo, make changes in `modules/`, and submit a PR!