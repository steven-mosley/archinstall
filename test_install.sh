#!/usr/bin/env bats

# Setup - runs before each test
setup() {
    # Create temp directory for test artifacts
    export TMPDIR="$(mktemp -d)"
    
    # Source the script but mock dangerous functions
    # Save original functions that we'll mock
    source "${BATS_TEST_DIRNAME}/install.sh" || true
    
    # Mock external commands to prevent actual system changes
    function check_boot_media() { return 0; }
    function check_internet() { return 0; }
    function check_uefi() { return 0; }
    function optimize_mirrors() { return 0; }
    function create_disk_menu() { selected_disk="/dev/mock"; }
    function verify_disk_space() { return 0; }
    function wipe_partitions() { return 0; }
    function create_partition_menu() { partition_choice="1"; }
    function perform_partitioning() { return 0; }
    function install_base_system() { return 0; }
    function setup_network() { return 0; }
    function configure_system() { return 0; }
    function setup_user_accounts() { return 0; }
    function cleanup() { return 0; }
    function log() { echo "$@"; }
    function prompt() { return 0; }

    # Prevent actual exit in tests
    function exit() { return "$1"; }
    
    # Prevent actual curl requests
    function curl() { 
        if [[ "$*" == *"VERSION"* ]]; then
            echo "0.1.0"
        fi
    }
    
    # Prevent actual clear
    function clear() { return 0; }
    
    # Mock EUID for root check tests
    export BATS_MOCK_EUID=$EUID
}

# Teardown - runs after each test
teardown() {
    rm -rf "$TMPDIR"
}

# Test root check
@test "Should exit if not run as root" {
    EUID=1000
    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Run as root" ]]
}

# Test version flag
@test "Should display version when --version flag is used" {
    run parse_args --version
    [[ "$output" =~ "Archinstall v0.1.0" ]]
}

# Test debug flag 
@test "Should set DEBUG when --debug flag is passed" {
    DEBUG=0
    parse_args --debug
    [ "$DEBUG" -eq 1 ]
}

# Test unsupported boot media flag
@test "Should set UNSUPPORTED when --unsupported-boot-media flag is passed" {
    UNSUPPORTED=0
    parse_args --unsupported-boot-media
    [ "$UNSUPPORTED" -eq 1 ]
}

# Test check version flag
@test "Should set CHECK_VERSION when --check-version flag is passed" {
    CHECK_VERSION=0
    parse_args --check-version
    [ "$CHECK_VERSION" -eq 1 ]
}

# Test skip boot check flag
@test "Should set SKIP_BOOT_CHECK when --skip-boot-check flag is passed" {
    SKIP_BOOT_CHECK=0
    parse_args --skip-boot-check
    [ "$SKIP_BOOT_CHECK" -eq 1 ]
}

# Test shell option
@test "Should set DEFAULT_SHELL when --shell option is passed" {
    parse_args --shell=zsh
    [ "$DEFAULT_SHELL" = "zsh" ]
}

# Test locale option
@test "Should set DEFAULT_LOCALE when --locale option is passed" {
    parse_args --locale=en_US.UTF-8
    [ "$DEFAULT_LOCALE" = "en_US.UTF-8" ]
}

# Test timezone option
@test "Should set DEFAULT_TZ when --timezone option is passed" {
    parse_args --timezone=America/New_York
    [ "$DEFAULT_TZ" = "America/New_York" ]
}

# Test invalid option
@test "Should exit with error on invalid option" {
    run parse_args --invalid-option
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]]
}

# Test check_version function when versions match
@test "check_version should return success when versions match" {
    # Mock the curl call to return the same version
    function curl() { echo "0.1.0"; }
    run check_version
    [ "$status" -eq 0 ]
    [[ "$output" =~ "latest version" ]]
}

# Test check_version function when remote version is newer
@test "check_version should prompt when remote version is newer" {
    # Mock curl and prompt for this test
    function curl() { echo "0.2.0"; }
    function prompt() { echo "y"; }
    
    run check_version
    [ "$status" -eq 0 ]
    [[ "$output" =~ "New version available" ]]
}

# Test basic flow of main function with mocked dependencies
@test "main function should run without errors when dependencies are met" {
    # Skip dangerous operations with mocks
    function check_boot_media() { return 0; }
    function check_internet() { return 0; }
    function check_uefi() { return 0; }
    
    run main --debug --skip-boot-check
    [ "$status" -eq 0 ]
}