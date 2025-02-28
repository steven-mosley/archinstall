#!/usr/bin/env bats

load ../test_helper

setup() {
  # Set flag to indicate we're running in a test environment
  export BATS_TEST_NAME="$BATS_TEST_DESCRIPTION"
  
  # Source the functions
  source "${BATS_TEST_DIRNAME}/../../functions.sh"
}

teardown() {
  # Clean up any test artifacts
  true
}

@test "log function formats messages correctly" {
  run log "Test message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[LOG]"* ]]
  [[ "$output" == *"Test message"* ]]
}

@test "error function exits with status 1" {
  # Override exit to prevent actual exit
  function exit() { echo "Would exit with $1"; return $1; }
  export -f exit
  
  run error "Test error message"
  
  echo "Output: $output" >&3
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR:"* ]]
  [[ "$output" == *"Test error"* ]]
}

@test "parse_args correctly handles debug flag" {
  parse_args "--debug"
  [ "$DEBUG" -eq 1 ]
}

@test "parse_args correctly handles shell option" {
  parse_args "--shell=zsh"
  [ "$DEFAULT_SHELL" == "zsh" ]
}

@test "check_root fails when not root" {
  # Mock functions instead of trying to set EUID
  function id() { echo 1000; }
  export -f id
  
  run check_root
  [ "$status" -eq 1 ]
  [[ "$output" == *"root"* ]]
}

@test "check_root succeeds when root" {
  # Mock id to simulate being root
  function id() { echo 0; }
  export -f id
  
  run check_root
  echo "Output: $output" >&3
  echo "Status: $status" >&3
  [ "$status" -eq 0 ]
}
