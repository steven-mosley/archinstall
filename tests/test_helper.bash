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

# Fix path handling to prevent double slashes

# Find the script directory without trailing slash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Line 28: Load the script under test properly
load_script() {
  local script_name="$1"
  source "${PROJECT_ROOT}/${script_name#/}"
}

# Line 38: Include files properly
include_file() {
  local file_name="$1"
  source "${PROJECT_ROOT}/${file_name#/}"
}

# Set up common test environment
setup_test_env() {
  # Create mock directory structure
  mkdir -p /tmp/archinstall_test/proc
  mkdir -p /tmp/archinstall_test/sys/firmware/efi/efivars
  
  # Export variables
  export TEST_DIR="/tmp/archinstall_test"
}

# Clean up test environment
cleanup_test_env() {
  rm -rf /tmp/archinstall_test
}
