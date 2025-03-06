#!/usr/bin/env python3
# archinstall.py - Arch Linux Installation Script

import os
import sys
import argparse
from pathlib import Path

# Import modules
from modules.utils import log, error, setup_logging, show_progress, prompt, TEST_MODE
from modules.checks import check_architecture, check_boot_media, check_internet, check_uefi, optimize_mirrors
from modules.config import read_config
from modules.disk import create_disk_menu, verify_disk_space, wipe_partitions
from modules.disk import create_partition_menu
from modules.filesystem import install_base_system, setup_filesystem
from modules.system import configure_system, setup_user_accounts, setup_network, set_system_clock
from modules.update import get_current_version, check_for_updates, update_script

class ArchInstall:
    def __init__(self):
        # Read version from VERSION file
        script_dir = Path(__file__).parent.resolve()
        version_file = os.path.join(script_dir, "VERSION")
        
        if os.path.exists(version_file):
            with open(version_file, 'r') as f:
                self.version = f.read().strip()
        else:
            self.version = "0.1.0"
            
        self.debug = False
        self.unsupported = False
        self.check_version = False
        self.skip_boot_check = False
        self.default_shell = "bash"
        self.default_locale = "en_US.UTF-8"
        self.default_tz = "UTC"
        self.test_mode = False
        self.mock_root = ""
        self.log_file = ""
        self.selected_disk = None
        self.partition_choice = None
        self.uefi_mode = False
        self.btrfs_config = {}
        self.root_partition = None
        self.efi_partition = None
        self.auto_update = True

    def parse_args(self):
        """Parse command line arguments"""
        parser = argparse.ArgumentParser(description='Arch Linux Installation Script')
        parser.add_argument('--debug', action='store_true', help='Enable debug output')
        parser.add_argument('--unsupported-boot-media', action='store_true', help='Skip boot media verification')
        parser.add_argument('--check-version', action='store_true', help='Check version and exit')
        parser.add_argument('--update', action='store_true', help='Check for updates and install if available')
        parser.add_argument('--skip-boot-check', action='store_true', help='Skip boot check')
        parser.add_argument('--no-update', action='store_true', help='Skip automatic update check')
        parser.add_argument('--version', action='store_true', help='Print version and exit')
        parser.add_argument('--test', action='store_true', help='Run in test mode')
        parser.add_argument('--shell', default='bash', help='Default shell to install')
        parser.add_argument('--locale', default='en_US.UTF-8', help='Default locale')
        parser.add_argument('--timezone', default='UTC', help='Default timezone')
        
        args = parser.parse_args()
        
        self.debug = args.debug
        self.unsupported = args.unsupported_boot_media
        self.check_version = args.check_version
        self.skip_boot_check = args.skip_boot_check
        self.test_mode = args.test
        self.default_shell = args.shell
        self.default_locale = args.locale
        self.default_tz = args.timezone
        self.auto_update = not args.no_update
        
        if args.version:
            print(f"Archinstall v{self.version}")
            sys.exit(0)
            
        if args.check_version:
            check_for_updates(print_message=True)
            sys.exit(0)
            
        if args.update:
            if update_script():
                log("Update process completed")
            else:
                error("Update failed")
            sys.exit(0)
        
        if self.test_mode:
            self.skip_boot_check = True
            global TEST_MODE
            TEST_MODE = True

    def check_root(self):
        """Check if script is run as root"""
        if os.geteuid() != 0 and not self.test_mode:
            error("This script must be run as root")
            sys.exit(1)

    def load_configs(self):
        """Load configuration files"""
        script_dir = Path(__file__).parent.resolve()
        
        # Load BTRFS configuration
        btrfs_config_path = os.path.join(script_dir, "config/btrfs_options.conf")
        self.btrfs_config = read_config(btrfs_config_path)
        
        if self.debug:
            log(f"Loaded BTRFS config: {self.btrfs_config}")

    def setup_environment(self):
        """Setup environment and create log directory"""
        script_dir = Path(__file__).parent.resolve()
        
        if self.test_mode:
            os.makedirs('/tmp/archinstall_logs', exist_ok=True)
            self.log_file = '/tmp/archinstall_logs/install.log'
        else:
            os.makedirs('/var/log/archinstall', exist_ok=True)
            self.log_file = '/var/log/archinstall/install.log'
        
        setup_logging(self.log_file)
        
        if self.debug:
            log(f"Script path: {script_dir}")
            log(f"Test mode: {self.test_mode}")
            log(f"Debug mode: {self.debug}")
        
        # Load configuration files
        self.load_configs()

    def run(self):
        """Main execution function"""
        print("\n=========================================")
        print("       Arch Linux Installation Script     ")
        print(f"              v{self.version}             ")
        print("=========================================\n")
        
        self.parse_args()
        
        if not self.test_mode:
            self.check_root()
        
        self.setup_environment()
        
        # Check for updates if auto-update is enabled and internet is available
        if self.auto_update and check_internet():
            log("Checking for updates...")
            update_available, _, _ = check_for_updates(print_message=False)
            
            if update_available and prompt("A new version is available. Update now?"):
                if update_script():
                    log("Update successful! Please restart the script.")
                    return 0
                else:
                    log("Update failed. Continuing with current version.")
        
        log(f"Starting Arch Linux installation (v{self.version})")
        
        # Check system requirements
        if not check_architecture():
            return 1
        
        if not self.skip_boot_check:
            if not check_boot_media():
                return 1
        
        if not check_internet():
            return 1
            
        self.uefi_mode = check_uefi()
        
        # Set system clock
        set_system_clock()
        
        # Update and optimize pacman mirrors
        optimize_mirrors()
        
        # Disk setup
        self.selected_disk = create_disk_menu()
        if not self.selected_disk:
            return 1
            
        if not verify_disk_space(self.selected_disk):
            return 1
        
        if not wipe_partitions(self.selected_disk):
            error("User canceled installation")
            return 1
            
        self.partition_choice = create_partition_menu()
        
        # Determine filesystem type
        fs_type = "btrfs" if self.partition_choice == 1 else "ext4"
        
        if self.partition_choice == 1 or self.partition_choice == 2:
            # Get partition layout from disk module
            partition_info = self.prepare_partitions()
            if not partition_info:
                return 1
                
            self.root_partition = partition_info["root"]
            self.efi_partition = partition_info.get("efi")
            
            # Setup filesystem with the correct partitions
            if not setup_filesystem(self.root_partition, fs_type, self.efi_partition, 
                                    self.btrfs_config if fs_type == "btrfs" else None):
                return 1
        else:
            # For manual partitioning, user has already set up filesystems
            log("Using manually created partitions")
        
        # System installation
        if not install_base_system(self.uefi_mode):
            return 1
            
        if not setup_network():
            log("Warning: Network setup may be incomplete")
        
        if not configure_system(self.default_locale, self.default_tz, self.selected_disk, self.uefi_mode):
            return 1
            
        if not setup_user_accounts(self.default_shell):
            return 1
        
        log("Installation complete! You can now reboot into your new Arch Linux system.")
        print("\n=========================================")
        print("       Installation Complete!            ")
        print("=========================================")
        print("\nYou can now reboot into your new Arch Linux system.")
        print("After rebooting, remove the installation media and log in with your user account.")
        
        return 0
        
    def prepare_partitions(self):
        """Create partitions and return partition information"""
        from modules.disk import create_partitions
        return create_partitions(self.selected_disk, self.partition_choice, self.uefi_mode)

if __name__ == "__main__":
    installer = ArchInstall()
    sys.exit(installer.run())