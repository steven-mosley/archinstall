#!/bin/bash
# Run all tests to verify the entire test suite

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Make sure everything has correct permissions
bash "$SCRIPT_DIR/fix_permissions.sh"

echo "==== Running minimal install test ===="
bash "$SCRIPT_DIR/minimal-install.sh"

echo ""
echo "==== Running sudo minimal install test ===="
# Use our wrapper for sudo tests
sudo "$SCRIPT_DIR/sudo_test_wrapper.sh" "$SCRIPT_DIR/minimal-install.sh"

echo ""
echo "==== Running direct run test ===="
bash "$SCRIPT_DIR/debug_direct_run.sh"

echo ""
echo "==== Running trace test ===="
bash "$SCRIPT_DIR/trace_run.sh"

echo ""
echo "==== Running BATS tests ===="

# Run BATS tests if BATS is installed
if command -v bats &>/dev/null; then
  bats "$SCRIPT_DIR/integration/install_flow.bats"
else
  echo "BATS not installed, skipping BATS tests"
fi

echo ""
echo "✅ All tests completed successfully!"
