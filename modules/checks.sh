#!/bin/bash
# Module with system check functions

# Make sure we don't accidentally exit in test mode
if [[ "$TEST_MODE" == "1" ]]; then
  set +e
fi

# Check if architecture is supported
check_architecture() {
  local arch
  arch=$(uname -m)
  
  if [[ "$arch" != "x86_64" && "$arch" != "aarch64" ]]; then
    if [[ "$TEST_MODE" == "1" ]]; then
      log "WARNING: Unsupported architecture $arch. Continuing in test mode."
      return 0
    else
      error "Unsupported architecture: $arch"
    fi
  fi
  
  log "Architecture $arch is supported"
  return 0
}

# This will be executed when the module is sourced
if [[ "$DEBUG" == "1" ]]; then
  echo "DEBUG: checks.sh module loaded successfully"
fi
