#!/usr/bin/env bash

# Mock common commands to prevent actual execution
function pacstrap() { echo "MOCK: pacstrap $*"; return 0; }
function sgdisk() { echo "MOCK: sgdisk $*"; return 0; }
function reflector() { echo "MOCK: reflector $*"; return 0; }
function lsblk() { 
  if [[ "$*" == *"-d -o NAME -n"* ]]; then
    echo "sda"
    echo "sdb"
  else
    echo "NAME  SIZE MODEL"
    echo "sda   20G  MOCK_DISK1"
    echo "sdb   40G  MOCK_DISK2"
  fi
  return 0
}
function blockdev() { echo "10737418240"; return 0; } # 10GB

# Helper function to create test files
create_test_file() {
  local path=$1
  local content=$2
  mkdir -p "$(dirname "$path")"
  echo "$content" > "$path"
}

// Set up common test environment
setup_test_env() {
  // Create mock directory structure
  mkdir -p /tmp/archinstall_test/proc
  mkdir -p /tmp/archinstall_test/sys/firmware/efi/efivars
  
  // Export variables
  export TEST_DIR="/tmp/archinstall_test"
}

// Clean up test environment
cleanup_test_env() {
  rm -rf /tmp/archinstall_test
}
