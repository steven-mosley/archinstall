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
  run error "Test error"
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
  EUID=1000
  run check_root
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be run as root"* ]]
}

@test "check_root succeeds when root" {
  EUID=0
  run check_root
  [ "$status" -eq 0 ]
}
