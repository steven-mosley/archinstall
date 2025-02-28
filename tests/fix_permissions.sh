#!/bin/bash
# Script to fix permissions for all test scripts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Fixing permissions for test scripts..."

# Make all scripts in tests directory executable
find "$PROJECT_ROOT/tests" -name "*.sh" -exec chmod +x {} \;
echo "All test scripts are now executable"

# Ensure modules have correct permissions
mkdir -p "$PROJECT_ROOT/modules"
find "$PROJECT_ROOT/modules" -name "*.sh" -exec chmod +x {} \;
echo "All module scripts are now executable"

# Make sure install.sh is executable
chmod +x "$PROJECT_ROOT/install.sh"
echo "install.sh is now executable"

echo "All permissions fixed successfully"
