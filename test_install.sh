#!/usr/bin/env bats

setup() {
    # Get absolute path to the install.sh file
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh"
    
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

teardown() {
    if [ -d "$TMPDIR" ]; then
        rm -rf "$TMPDIR"
    fi
}

# Test root requirement
@test "Script should exit if not run as root" {
    run bash -c "EUID=1000; source ${BATS_TEST_DIRNAME}/install.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Run as root"* ]]
}

# Test version flag
@test "Script should display version with --version flag" {
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --version"
    [[ "$output" == *"Archinstall v0.1.0"* ]]
}

# Test parse_args function with various arguments
@test "parse_args should set DEBUG with --debug flag" {
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --debug"
    [ "$status" -eq 0 ]
    [ "$DEBUG" -eq 1 ]
}

@test "parse_args should set UNSUPPORTED with --unsupported-boot-media flag" {
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --unsupported-boot-media"
    [ "$status" -eq 0 ]
    [ "$UNSUPPORTED" -eq 1 ]
}

@test "parse_args should set CHECK_VERSION with --check-version flag" {
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --check-version"
    [ "$status" -eq 0 ]
    [ "$CHECK_VERSION" -eq 1 ]
}

@test "parse_args should set SKIP_BOOT_CHECK with --skip-boot-check flag" {
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --skip-boot-check"
    [ "$status" -eq 0 ]
    [ "$SKIP_BOOT_CHECK" -eq 1 ]
}

@test "parse_args should set DEFAULT_SHELL with --shell option" {
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --shell=zsh"
    [ "$status" -eq 0 ]
    [ "$DEFAULT_SHELL" = "zsh" ]
}

@test "parse_args should set DEFAULT_LOCALE with --locale option" {
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --locale=fr_FR.UTF-8"
    [ "$status" -eq 0 ]
    [ "$DEFAULT_LOCALE" = "fr_FR.UTF-8" ]
}

@test "parse_args should set DEFAULT_TZ with --timezone option" {
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --timezone=Europe/Berlin"
    [ "$status" -eq 0 ]
    [ "$DEFAULT_TZ" = "Europe/Berlin" ]
}

@test "parse_args should exit with error on invalid option" {
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --invalid-option"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# Test check_version function
@test "check_version should proceed when version matches" {
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && check_version"
    [ "$status" -eq 0 ]
    [[ "$output" == *"You're running the latest version"* ]]
}

@test "check_version should handle network errors gracefully" {
    function curl() { return 1; }
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && check_version"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Couldn't fetch a valid version"* ]]
}

@test "check_version should detect newer versions" {
    function curl() { 
        if [[ "$*" == *"VERSION"* ]]; then
            echo "0.2.0"
            return 0
        fi
    }
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && check_version"
    [ "$status" -eq 0 ]
    [[ "$output" == *"New version available"* ]]
}

@test "check_version should handle invalid version formats" {
    function curl() { 
        if [[ "$*" == *"VERSION"* ]]; then
            echo "not-a-version"
            return 0
        fi
    }
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && check_version"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Couldn't fetch a valid version"* ]]
}

# Test main function with mocked dependencies
@test "main function should execute installation flow without errors" {
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && main --debug --skip-boot-check"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting Arch Linux installation"* ]]
    [[ "$output" == *"Installation complete"* ]]
}

@test "main function should check version when --check-version is specified" {
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && main --check-version"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Checking for updates"* ]]
}

@test "main function should skip boot check when --skip-boot-check is specified" {
    function check_boot_media() { 
        echo "This should not be called"
        return 1
    }
    
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && main --skip-boot-check"
    [ "$status" -eq 0 ]
    [[ ! "$output" == *"This should not be called"* ]]
}

@test "main function should handle errors during installation" {
    function install_base_system() { return 1; }
    
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && main"
    [ "$status" -eq 1 ]
}

@test "main function should pass arguments to parse_args" {
    function parse_args() { 
        echo "Args received: $*"
    }
    
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && main --debug --skip-boot-check"
    [[ "$output" == *"Args received: --debug --skip-boot-check"* ]]
}