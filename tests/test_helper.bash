#!/usr/bin/env bash

# Find the absolute path to project
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create modules directory before anything else
mkdir -p "${PROJECT_ROOT}/modules"

# Mock common commands to prevent actual execution
function pacstrap() { echo "MOCK: pacstrap $*"; return 0; }
function sgdisk() { echo "MOCK: sgdisk $*"; return 0; }
function reflector() { echo "MOCK: reflector $*"; return 0; }
function blockdev() { echo "10737418240"; return 0; } # 10GB
function curl() { echo "0.1.0"; return 0; }
function ping() { echo "MOCK: ping successful"; return 0; }

# Function for lsblk with different output formats
function lsblk() {
  if [[ "$*" == *"-d -o NAME -n"* ]]; then
    echo "sda"
    echo "sdb"
  elif [[ "$*" == *"-d"* ]]; then
    echo "NAME SIZE MODEL"
    echo "sda  20G  MOCK_DISK1"
    echo "sdb  40G  MOCK_DISK2"
  else
    echo "NAME SIZE MODEL"
    echo "sda  20G  MOCK_DISK1"
    echo "sdb  40G  MOCK_DISK2"
  fi
  return 0
}

# Mock filesystem commands in test environment
function grep() {
  if [[ "$*" == *"/proc/cmdline"* ]]; then
    echo "BOOT_IMAGE=/boot/vmlinuz-linux root=UUID=abc123 rw quiet archiso"
    return 0
  fi
  # Pass through to real grep for other cases
  command grep "$@"
}

# Helper function to create test files
create_test_file() {
  local path=$1
  local content=$2
  mkdir -p "$(dirname "$path")"
  echo "$content" > "$path"
}

# Run in test mode by default
export TEST_MODE=1
export DEBUG=1

# Set up common test environment
setup_test_env() {
  # Create mock directory structure for system checks
  mkdir -p /tmp/archinstall_test/proc
  mkdir -p /tmp/archinstall_test/sys/firmware/efi/efivars
  
  # Create module files if they don't exist
  for module in checks disk filesystem network system user utils; do
    MODULE_FILE="${PROJECT_ROOT}/modules/${module}.sh"
    if [[ ! -f "$MODULE_FILE" ]]; then
      echo "#!/bin/bash" > "$MODULE_FILE"
      echo "# Mock module for testing" >> "$MODULE_FILE"
      chmod +x "$MODULE_FILE"
    fi
  done
  
  # Export variables
  export TEST_DIR="/tmp/archinstall_test"
  export PATH="${PROJECT_ROOT}/tests/mocks:$PATH"
}

# Clean up test environment
cleanup_test_env() {
  rm -rf /tmp/archinstall_test
  rm -rf /tmp/archinstall_logs
  rm -rf /tmp/archinstall_mockroot
}
