#!/usr/bin/env bats

load ../test_helper

setup() {
    # Create temp directory for test artifacts
    export TMPDIR="$(mktemp -d)"
    
    # Mock functions to prevent actual system changes
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
    
    # Source the script with mocks in place
    source "${BATS_TEST_DIRNAME}/../../install.sh"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "Should exit if not run as root" {
    EUID=1000
    run check_root
    [ "$status" -eq 1 ]
    [[ "$output" =~ "must be run as root" ]]
}

@test "Should display version when --version flag is used" {
    run parse_args --version
    [[ "$output" =~ "Archinstall v0.1.0" ]]
}

@test "Should set DEBUG when --debug flag is passed" {
    DEBUG=0
    parse_args --debug
    [ "$DEBUG" -eq 1 ]
}

@test "Should set UNSUPPORTED when --unsupported-boot-media flag is passed" {
    UNSUPPORTED=0
    parse_args --unsupported-boot-media
    [ "$UNSUPPORTED" -eq 1 ]
}

@test "Should set CHECK_VERSION when --check-version flag is passed" {
    CHECK_VERSION=0
    parse_args --check-version
    [ "$CHECK_VERSION" -eq 1 ]
}

@test "Should set SKIP_BOOT_CHECK when --skip-boot-check flag is passed" {
    SKIP_BOOT_CHECK=0
    parse_args --skip-boot-check
    [ "$SKIP_BOOT_CHECK" -eq 1 ]
}

@test "Should set DEFAULT_SHELL when --shell option is passed" {
    parse_args --shell=zsh
    [ "$DEFAULT_SHELL" = "zsh" ]
}

@test "Should set DEFAULT_LOCALE when --locale option is passed" {
    parse_args --locale=en_US.UTF-8
    [ "$DEFAULT_LOCALE" = "en_US.UTF-8" ]
}

@test "Should set DEFAULT_TZ when --timezone option is passed" {
    parse_args --timezone=America/New_York
    [ "$DEFAULT_TZ" = "America/New_York" ]
}

@test "Should exit with error on invalid option" {
    run parse_args --invalid-option
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]]
}

@test "check_version should return success when versions match" {
    # Mock the curl call to return the same version
    function curl() { echo "0.1.0"; }
    run check_version
    [ "$status" -eq 0 ]
    [[ "$output" =~ "latest version" ]]
}

@test "check_version should prompt when remote version is newer" {
    # Mock curl and prompt for this test
    function curl() { echo "0.2.0"; }
    function prompt() { echo "y"; }
    
    run check_version
    [ "$status" -eq 0 ]
    [[ "$output" =~ "New version available" ]]
}

@test "main function should run without errors when dependencies are met" {
    # Skip dangerous operations with mocks
    function check_boot_media() { return 0; }
    function check_internet() { return 0; }
    function check_uefi() { return 0; }
    
    run main --debug --skip-boot-check
    [ "$status" -eq 0 ]
}

@test "main function should check version when --check-version is specified" {
    run bash -c "source ${BATS_TEST_DIRNAME}/../../install.sh && main --check-version"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Checking for updates"* ]]
}

@test "main function should skip boot check when --skip-boot-check is specified" {
    function check_boot_media() { echo "This should not be called"; return 1; }
    run bash -c "source ${BATS_TEST_DIRNAME}/../../install.sh && main --skip-boot-check"
    [ "$status" -eq 0 ]
    [[ ! "$output" == *"This should not be called"* ]]
}

@test "main function should handle errors during installation" {
    function install_base_system() { return 1; }
    run bash -c "source ${BATS_TEST_DIRNAME}/../../install.sh && main"
    [ "$status" -eq 1 ]
}

@test "main function should pass arguments to parse_args" {
    function parse_args() { echo "Args received: $*"; }
    run bash -c "source ${BATS_TEST_DIRNAME}/../../install.sh && main --debug --skip-boot-check"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Args received: --debug --skip-boot-check"* ]]
}
