# Arch Linux Installation Script

A simple script for installing Arch Linux with sensible defaults.

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

## Development

### Setting Up the Repository

After cloning the repository, initialize the submodules:

```bash
git submodule init
git submodule update
```

Alternatively, use the provided setup script:

```bash
./setup_test_env.sh
```

## Testing

The script includes various test files to ensure it functions correctly:

### Running Tests

To run all tests:

```bash
bash tests/all_tests.sh
```

To run specific tests:

1. Minimal install test (non-root):
```bash
bash tests/minimal-install.sh
```

2. Minimal install test (with root):
```bash
sudo tests/sudo_test_wrapper.sh tests/minimal-install.sh
```

3. Direct run test:
```bash
bash tests/debug_direct_run.sh
```

4. BATS tests:
```bash
bats tests/integration/install_flow.bats
```

### Test Structure

- `tests/minimal-install.sh`: Tests each function in isolation
- `tests/debug_direct_run.sh`: Runs with full debug output
- `tests/trace_run.sh`: Traces execution step by step
- `tests/integration/install_flow.bats`: BATS integration tests
- `tests/sudo_test_wrapper.sh`: Helper for running tests as root

### Mock Commands

Mock commands are located in `tests/integration/mocks/`:

- `lsblk`: Simulates disk listing
- `sgdisk`: Simulates partition manipulation
- `blockdev`: Simulates block device information
- `ping`: Simulates connectivity checking
- `pacstrap`: Simulates package installation
- `reflector`: Simulates mirror list optimization
- `arch-chroot`: Simulates chroot operations

## Project Structure

```
archinstall/
├── install.sh         # Main installation script
├── modules/           # Script modules
│   ├── disk.sh        # Disk handling functions
│   ├── network.sh     # Network configuration
│   └── system.sh      # System configuration
├── tests/             # Test suite
│   └── install.bats   # Main test file
├── bats-core/         # BATS testing framework (submodule)
└── VERSION            # Version file
```