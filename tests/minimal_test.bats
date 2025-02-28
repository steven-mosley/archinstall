#!/usr/bin/env bats

setup() {
  # Pre-define functions to prevent execution during source
  function main() { echo "MOCK MAIN"; }
  function check_internet() { return 0; }
  function log() { echo "MOCK LOG: $*"; }
  function check_boot_media() { return 0; }
}

@test "Simple test" {
  run echo "hello"
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "Can source install.sh" {
  source ./install.sh
  [ -n "$(declare -F main)" ] # Check if main function exists
}
