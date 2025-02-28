#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_test_env
  
  # Mock read command to automatically provide input
  function read() {
    if [[ "$*" == *"Select a disk"* ]]; then
      echo "1" # Select first disk
    elif [[ "$*" == *"partitioning scheme"* ]]; then
      echo "1" # Select standard partitioning
    elif [[ "$*" == *"[y/n]"* ]]; then
      echo "y" # Always say yes
    fi
    return 0
  }

  # Override functions that need root to prevent real execution
  function check_root() { return 0; }
  function check_boot_media() { return 0; }
  
  # Source the main script with overrides
  source "${BATS_TEST_DIRNAME}/../../install.sh"
}

teardown() {
  cleanup_test_env
}

@test "Main function executes without errors" {
  # Mock necessary functions to prevent actual execution
  function install_base_system() { echo "MOCK: install_base_system"; return 0; }
  function setup_network() { echo "MOCK: setup_network"; return 0; }
  function configure_system() { echo "MOCK: configure_system"; return 0; }
  function setup_user_accounts() { echo "MOCK: setup_user_accounts"; return 0; }
  function cleanup() { echo "MOCK: cleanup"; return 0; }
  
  # Skip some checks to simplify testing
  SKIP_BOOT_CHECK=1
  
  run main
  [ "$status" -eq 0 ]
  [[ "$output" == *"Starting Arch Linux installation"* ]]
  [[ "$output" == *"Installation complete"* ]]
}

@test "Check version function works correctly" {
  function curl() { echo "0.1.1"; return 0; }
  
  run check_version
  [ "$status" -eq 0 ]
  [[ "$output" == *"New version available"* ]]
}
