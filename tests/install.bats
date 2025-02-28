#!/usr/bin/env bats

# Include the existing test file content
source "../test_install.sh"

setup() {
    # Get absolute path to the install.sh file
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh"
    
    # Create a temporary directory for test artifacts
    export TMPDIR="$(mktemp -d)"
    
    # Define required variables and functions BEFORE sourcing
    export YELLOW=""
    export NC=""
    log() { echo "$@"; }
    prompt() { echo "y"; }
    
    # Mock the module sourcing
    function source_modules() {
        echo "Mocking module sourcing"
    }
    
    # Source the script with absolute path
    source "$SCRIPT_PATH" || echo "Sourcing failed: $?"
    
    # Override system-modifying functions
    function check_boot_media() { return 0; }
    function check_internet() { return 0; }
    function check_uefi() { return 0; }
    function optimize_mirrors() { return 0; }
    function create_disk_menu() { selected_disk="/dev/sda"; }
    function verify_disk_space() { return 0; }
    function wipe_partitions() { return 0; }
    function create_partition_menu() { partition_choice="1"; }
    function perform_partitioning() { return 0; }
    function install_base_system() { return 0; }
    function setup_network() { return 0; }
    function configure_system() { return 0; }
    function setup_user_accounts() { return 0; }
    function cleanup() { return 0; }
    
    # Override exit to prevent actual termination
    function exit() { return "$1"; }
    
    # Mock clear to prevent terminal clearing
    function clear() { return 0; }
    
    # Mock curl to avoid actual network requests
    function curl() {
        if [[ "$*" == *"VERSION"* ]]; then
            echo "0.1.0"
            return 0
        fi
        return 1
    }
}

# ...existing code...
