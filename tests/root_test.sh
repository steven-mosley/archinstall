#!/bin/bash
# Test script specifically designed to run as root

# Exit on error
set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Set up environment
echo "Setting up root test environment..."
mkdir -p "$ROOT_DIR/modules"

# Create a temporary script to run as root
TMP_SCRIPT=$(mktemp)
cat > "$TMP_SCRIPT" <<EOF
#!/bin/bash

# Set environment variables
export TEST_MODE=1
export DEBUG=1

# Create modules if they don't exist
mkdir -p "$ROOT_DIR/modules"
for module in checks disk filesystem network system user utils; do
  if [ ! -f "$ROOT_DIR/modules/\$module.sh" ]; then
    echo "#!/bin/bash" > "$ROOT_DIR/modules/\$module.sh"
    echo "# Mock module for root testing" >> "$ROOT_DIR/modules/\$module.sh"
    chmod +x "$ROOT_DIR/modules/\$module.sh"
  fi
done

# Change to project root directory
cd "$ROOT_DIR"

# Run the script with test inputs
./install.sh --test --debug <<INPUTS
y
y
1
y
vim git htop
zsh
INPUTS
EOF

chmod +x "$TMP_SCRIPT"

# Ask for sudo password if needed
echo "Running test as root (requires sudo)..."
sudo bash "$TMP_SCRIPT"

# Cleanup
rm -f "$TMP_SCRIPT"

echo "Root test completed!"
