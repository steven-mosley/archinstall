#!/bin/bash

# Script to manually run and debug the install.sh script with test inputs

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SCRIPT="${TEST_DIR}/../install.sh"

# Setup test environment
export TEST_MODE=1
chmod +x "$INSTALL_SCRIPT"

# Create test input for additional packages
cat > "/tmp/test_input" <<EOF
sda
y
1
y
vim htop firefox
zsh
EOF

# Run the installation script with the test input
cat /tmp/test_input | bash "$INSTALL_SCRIPT" --test --debug "$@"

echo "======================================================="
echo "Test run completed. Exit code: $?"
