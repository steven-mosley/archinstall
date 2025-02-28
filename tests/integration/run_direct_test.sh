#!/bin/bash
# This script runs the installation test directly, bypassing BATS for easier debugging

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Create mock directories
mkdir -p "$SCRIPT_DIR/mocks"
export PATH="$SCRIPT_DIR/mocks:$PATH"

# Make sure mock commands are executable
chmod +x "$SCRIPT_DIR"/mocks/* 2>/dev/null || true

# Prepare environment
export TEST_MODE=1
export DEBUG=1

# Show which lsblk we'll use
echo "Using: $(which lsblk)"
echo "Path: $PATH"
echo "Mock files:"
ls -la "$SCRIPT_DIR/mocks/"

echo "======================================================="
echo "Running custom installation test"
echo "======================================================="

# Run the test with input
"$ROOT_DIR/install.sh" --test --debug <<INPUTS
1
y
1
y
vim git firefox
zsh
INPUTS

echo "======================================================="
echo "Test exit code: $?"
echo "======================================================="
