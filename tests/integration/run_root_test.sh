#!/bin/bash
# This script runs the installation test as root using sudo

# Get the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Create directories for mock commands
MOCK_DIR="$SCRIPT_DIR/mocks"
mkdir -p "$MOCK_DIR"

# Ensure modules directory exists
MODULE_DIR="$ROOT_DIR/modules"
mkdir -p "$MODULE_DIR"

# Make sure permissions are correct
echo "Setting permissions..."
chmod -R a+rx "$SCRIPT_DIR"
chmod -R a+rx "$ROOT_DIR/modules"

echo "===== RUNNING ROOT TEST ====="
echo "Module dir: $MODULE_DIR"

# Create a temporary script with root privileges
TMP_SCRIPT="/tmp/root_test_$$.sh"
cat > "$TMP_SCRIPT" <<EOF
#!/bin/bash
# Export path to include mock commands
export PATH="$MOCK_DIR:\$PATH"

# Export test mode flag
export TEST_MODE=1
export DEBUG=1

# Create empty module files if needed
echo "Creating module files..."
mkdir -p "$MODULE_DIR"
for module in checks disk filesystem network system user utils; do
  if [ ! -f "$MODULE_DIR/\$module.sh" ]; then
    echo "#!/bin/bash" > "$MODULE_DIR/\$module.sh"
    echo "# Mock module for \$module" >> "$MODULE_DIR/\$module.sh"
    chmod +x "$MODULE_DIR/\$module.sh"
  fi
done

# Run the actual test
cd "$ROOT_DIR"
./install.sh --test --debug <<INPUTS
y
y
1
y
vim git firefox
zsh
INPUTS

EOF

chmod +x "$TMP_SCRIPT"

# Run the script as root
sudo bash "$TMP_SCRIPT"
RESULT=$?

# Clean up
rm -f "$TMP_SCRIPT"

echo "===== ROOT TEST COMPLETED WITH EXIT CODE: $RESULT ====="
exit $RESULT
