#!/usr/bin/env bats

load ../test_helper

setup() {
  # Override functions that would have side effects
  function error() { echo "ERROR: $*"; return 1; }
  
  # Source the main script with overrides
  source "${BATS_TEST_DIRNAME}/../../install.sh"
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
  # Mock the exit function to prevent actual exit
  function exit() { return $1; }
  
  # Run the error function
  run error "Test error message"
  
  # Verify it outputs ERROR prefix and returns 1
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
  # Mock functions to simulate being root
  function id() { echo 0; }
  export -f id
  
  run check_root
  [ "$status" -eq 0 ]
}
