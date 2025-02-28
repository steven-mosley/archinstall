#!/bin/bash
# Script to configure proper mock environment for tests run with sudo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MOCK_DIR="$SCRIPT_DIR/integration/mocks"

# Create mock command directory
mkdir -p "$MOCK_DIR"

# Ensure mocks for all required commands are present
echo "Creating mock commands for sudo environment..."

# Mock sgdisk
cat > "$MOCK_DIR/sgdisk" <<'EOF'
#!/bin/bash
echo "MOCK SUDO: sgdisk $*"
exit 0
EOF

# Mock blockdev
cat > "$MOCK_DIR/blockdev" <<'EOF'
#!/bin/bash
echo "10737418240" # 10GB
exit 0
EOF

# Mock ping
cat > "$MOCK_DIR/ping" <<'EOF'
#!/bin/bash
echo "MOCK SUDO: Ping successful"
exit 0
EOF

# Make all mock commands executable
find "$MOCK_DIR" -type f -exec chmod +x {} \;

# Create a wrapper script for running with sudo
cat > "$SCRIPT_DIR/sudo_test_wrapper.sh" <<EOF
#!/bin/bash
# Wrapper for running tests with sudo with proper environment

# Add mocks to PATH
export PATH="$MOCK_DIR:\$PATH"
export TEST_MODE=1
export DEBUG=1

# Test that mock commands are found
echo "Testing mock command availability:"
which sgdisk
which blockdev
which ping

# Run the actual test
cd "$PROJECT_ROOT"
"\$@"

exit \$?
EOF

chmod +x "$SCRIPT_DIR/sudo_test_wrapper.sh"

echo "Mock environment prepared for sudo tests"
echo "Run tests with: sudo $SCRIPT_DIR/sudo_test_wrapper.sh tests/minimal-install.sh"
