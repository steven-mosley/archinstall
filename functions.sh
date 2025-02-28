#!/bin/bash

# Log a message to stdout
log() {
  echo "[LOG] $1"
}

# Log an error and exit with status 1
error() {
  # Don't redirect to stderr during tests so BATS can capture output
  echo "ERROR: $1"
  exit 1
}

# Parse command line arguments
parse_args() {
  for arg in "$@"; do
    case $arg in
      --debug)
        DEBUG=1
        ;;
      --shell=*)
        DEFAULT_SHELL="${arg#*=}"
        ;;
      # Add other argument parsing as needed
    esac
  done
}

# Check if the script is run as root
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    # During tests, we want to output the message but not exit
    if [[ -n "$BATS_TEST_NAME" ]]; then
      echo "ERROR: This script must be run as root."
      return 1
    else
      error "This script must be run as root."
    fi
  fi
  return 0
}