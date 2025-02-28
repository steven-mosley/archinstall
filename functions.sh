#!/bin/bash

# Log a message to stdout
log() {
  echo "[LOG] $1"
}

# Log an error and exit with status 1
error() {
  echo "ERROR: $1" >&2
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
    error "This script must be run as root."
    return 1
  fi
  return 0
}