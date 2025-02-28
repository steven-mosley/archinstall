#!/bin/bash
# Wrapper for running tests with sudo with proper environment

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MOCK_DIR="$SCRIPT_DIR/integration/mocks"

# Add mocks to PATH
export PATH="$MOCK_DIR:$PATH"
export TEST_MODE=1
export DEBUG=1

# Show diagnostic info
echo "=== Diagnostics ==="
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "PROJECT_ROOT: $PROJECT_ROOT"
echo "MOCK_DIR: $MOCK_DIR"
echo "PATH: $PATH"
echo "USER: $(whoami)"
echo "PWD: $(pwd)"
echo "Test script to run: $1"

# Test that mock commands are found
echo ""
echo "Testing mock command availability:"
which sgdisk || echo "sgdisk not found!"
which blockdev || echo "blockdev not found!"
which ping || echo "ping not found!"
echo ""

# Verify the test script exists
TEST_SCRIPT="$PROJECT_ROOT/${1#$PROJECT_ROOT/}"
if [[ ! -f "$TEST_SCRIPT" ]]; then
  echo "ERROR: Test script not found: $TEST_SCRIPT"
  echo "Current directory contents:"
  ls -la "$(dirname "$TEST_SCRIPT")"
  exit 1
fi

# Make sure it's executable
chmod +x "$TEST_SCRIPT"

echo "=== Running Test Script ==="
echo "Executing: $TEST_SCRIPT"

# Run the actual test
cd "$PROJECT_ROOT"
bash "$TEST_SCRIPT"
EXIT_CODE=$?

echo ""
echo "Test completed with exit code: $EXIT_CODE"
exit $EXIT_CODE
