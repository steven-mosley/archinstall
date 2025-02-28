








































































































































































































}    [[ "$output" == *"Args received: --debug --skip-boot-check"* ]]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && main --debug --skip-boot-check"        }        echo "Args received: $*"    function parse_args() { @test "main function should pass arguments to parse_args" {}    [ "$status" -eq 1 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && main"        function install_base_system() { return 1; }@test "main function should handle errors during installation" {}    [[ ! "$output" == *"This should not be called"* ]]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && main --skip-boot-check"        }        return 1        echo "This should not be called"    function check_boot_media() { @test "main function should skip boot check when --skip-boot-check is specified" {}    [[ "$output" == *"Checking for updates"* ]]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && main --check-version"@test "main function should check version when --check-version is specified" {}    [[ "$output" == *"Installation complete"* ]]    [[ "$output" == *"Starting Arch Linux installation"* ]]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && main --debug --skip-boot-check"@test "main function should execute installation flow without errors" {# Test main function with mocked dependencies}    [[ "$output" == *"Couldn't fetch a valid version"* ]]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && check_version"    }        fi            return 0            echo "not-a-version"        if [[ "$*" == *"VERSION"* ]]; then    function curl() { @test "check_version should handle invalid version formats" {}    [[ "$output" == *"New version available"* ]]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && check_version"    }        fi            return 0            echo "0.2.0"        if [[ "$*" == *"VERSION"* ]]; then    function curl() { @test "check_version should detect newer versions" {}    [[ "$output" == *"Couldn't fetch a valid version"* ]]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && check_version"    function curl() { return 1; }@test "check_version should handle network errors gracefully" {}    [[ "$output" == *"You're running the latest version"* ]]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && check_version"@test "check_version should proceed when version matches" {# Test check_version function}    [[ "$output" == *"Unknown option"* ]]    [ "$status" -eq 1 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --invalid-option"@test "parse_args should exit with error on invalid option" {}    [ "$DEFAULT_TZ" = "Europe/Berlin" ]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --timezone=Europe/Berlin"@test "parse_args should set DEFAULT_TZ with --timezone option" {}    [ "$DEFAULT_LOCALE" = "fr_FR.UTF-8" ]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --locale=fr_FR.UTF-8"@test "parse_args should set DEFAULT_LOCALE with --locale option" {}    [ "$DEFAULT_SHELL" = "zsh" ]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --shell=zsh"@test "parse_args should set DEFAULT_SHELL with --shell option" {}    [ "$SKIP_BOOT_CHECK" -eq 1 ]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --skip-boot-check"@test "parse_args should set SKIP_BOOT_CHECK with --skip-boot-check flag" {}    [ "$CHECK_VERSION" -eq 1 ]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --check-version"@test "parse_args should set CHECK_VERSION with --check-version flag" {}    [ "$UNSUPPORTED" -eq 1 ]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --unsupported-boot-media"@test "parse_args should set UNSUPPORTED with --unsupported-boot-media flag" {}    [ "$DEBUG" -eq 1 ]    [ "$status" -eq 0 ]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --debug"@test "parse_args should set DEBUG with --debug flag" {# Test parse_args function with various arguments}    [[ "$output" == *"Archinstall v0.1.0"* ]]    run bash -c "source ${BATS_TEST_DIRNAME}/install.sh && parse_args --version"@test "Script should display version with --version flag" {# Test version flag}    [[ "$output" == *"Run as root"* ]]    [ "$status" -eq 1 ]    run bash -c "EUID=1000; source ${BATS_TEST_DIRNAME}/install.sh"@test "Script should exit if not run as root" {# Test root requirement}    fi        rm -rf "$TMPDIR"    if [ -d "$TMPDIR" ]; thenteardown() {}    }        return 1        fi            return 0            echo "0.1.0"        if [[ "$*" == *"VERSION"* ]]; then    function curl() {    # Mock curl to avoid actual network requests        function clear() { return 0; }    # Mock clear to prevent terminal clearing        function exit() { return "$1"; }    # Override exit to prevent actual termination        function cleanup() { return 0; }    function setup_user_accounts() { return 0; }    function configure_system() { return 0; }    function setup_network() { return 0; }    function install_base_system() { return 0; }    function perform_partitioning() { return 0; }    function create_partition_menu() { partition_choice="1"; }    function wipe_partitions() { return 0; }    function verify_disk_space() { return 0; }    function create_disk_menu() { selected_disk="/dev/sda"; }    function optimize_mirrors() { return 0; }    function check_uefi() { return 0; }    function check_internet() { return 0; }    function check_boot_media() { return 0; }    # Override system-modifying functions        source "$SCRIPT_PATH" || echo "Sourcing failed: $?"    # Source the script with absolute path        }        echo "Mocking module sourcing"    function source_modules() {    # Mock the module sourcing        prompt() { echo "y"; }    log() { echo "$@"; }    export NC=""    export YELLOW=""    # Define required variables and functions BEFORE sourcing        export TMPDIR="$(mktemp -d)"    # Create a temporary directory for test artifacts        SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh"    # Get absolute path to the install.sh filesetup() {#!/usr/bin/env bats