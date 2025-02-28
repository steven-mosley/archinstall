#!/bin/bash

# Simple non-Bats test to see what's happening
echo "=== DEBUGGING INSTALL.SH SOURCING ==="

# Define functions to prevent actual execution
function main() { echo "MAIN FUNCTION CALLED WITH ARGS: $*"; }
function check_internet() { echo "Mock check_internet called"; return 0; }
function log() { echo "LOG: $*"; }

# Now source the script after defining mocks
source ./install.sh || echo "Source failed with code $?"
declare -F main || echo "Main function not found after sourcing"

echo "=== END DEBUG ==="

# Now create a minimal Bats test file
cat > minimal_test.bats << 'EOF'
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
EOF

# Make it executable
chmod +x minimal_test.bats

echo "Now try running: bats minimal_test.bats"