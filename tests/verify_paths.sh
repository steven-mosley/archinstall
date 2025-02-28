#!/bin/bash
# A simple script to verify path calculations for debugging

# Get absolute script path
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Path Diagnostics ==="
echo "Script path: $SCRIPT_PATH"
echo "Script directory: $SCRIPT_DIR"
echo "Project root: $PROJECT_ROOT"
echo "Parent of project: $(cd "$PROJECT_ROOT/.." && pwd)"

echo "=== File Existence Tests ==="
echo "install.sh exists? $(test -f "$PROJECT_ROOT/install.sh" && echo "Yes" || echo "No")"
echo "modules dir exists? $(test -d "$PROJECT_ROOT/modules" && echo "Yes" || echo "No")"

echo "=== Directory Structure ==="
echo "Contents of project root:"
ls -la "$PROJECT_ROOT"

echo "=== Integration Path Calculation Test ==="
INTEGRATION_DIR="$PROJECT_ROOT/tests/integration"
echo "Integration directory: $INTEGRATION_DIR"
echo "Path back to project root: $(cd "$INTEGRATION_DIR/../.." && pwd)"

echo "=== BATS Path Simulation ==="
# Simulate what BATS would see
export BATS_TEST_DIRNAME="$INTEGRATION_DIR"
echo "BATS_TEST_DIRNAME: $BATS_TEST_DIRNAME" 
echo "install.sh from BATS_TEST_DIRNAME: $BATS_TEST_DIRNAME/../../install.sh"
echo "install.sh exists from BATS_TEST_DIRNAME? $(test -f "$BATS_TEST_DIRNAME/../../install.sh" && echo "Yes" || echo "No")"

echo "Done with path verification"
