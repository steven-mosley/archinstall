# Arch Linux Installation Script

An automated installation script for Arch Linux that simplifies the setup process.

## Features

- Guided installation process
- Disk partitioning options
- Network configuration
- User account setup
- Customizable shell, locale, and timezone settings

## Usage

```bash
sudo ./install.sh [options]
```

### Options

- `--shell=SHELL`: Set default shell (bash, zsh)
- `--locale=LOCALE`: Set system locale (e.g., en_US.UTF-8)
- `--timezone=TZ`: Set timezone (e.g., Europe/London)
- `--debug`: Enable debug mode
- `--unsupported-boot-media`: Allow installation on unsupported boot media
- `--check-version`: Check for script updates
- `--skip-boot-check`: Skip boot media verification
- `--version`: Display version information

## Testing

Run the test suite with:

```bash
cd tests
bats .
```

## Project Structure

```
archinstall/
├── install.sh         # Main installation script
├── modules/           # Script modules
│   ├── disk.sh        # Disk handling functions
│   ├── network.sh     # Network configuration
│   ├── system.sh      # System configuration
│   └── ...
├── tests/             # Test suite
│   ├── install.bats   # Main test file
│   └── ...
└── VERSION            # Version file
```