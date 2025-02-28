#!/bin/bash
# Directly runs the integration tests without BATS

# Exit on error but with verbose output
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==== Setting up environment ===="
# Setup mocks directory and include in PATH
mkdir -p "$SCRIPT_DIR/mocks"
export PATH="$SCRIPT_DIR/mocks:$PATH"

# Make sure all mock commands are executable
find "$SCRIPT_DIR/mocks" -type f -exec chmod +x {} \;
echo "Mock commands in path: $(which lsblk || echo "lsblk not found!")"

# Create necessary module files
mkdir -p "$PROJECT_ROOT/modules"
for module in checks disk filesystem network system user utils; do
  MODULE_FILE="$PROJECT_ROOT/modules/${module}.sh"
  if [[ ! -f "$MODULE_FILE" ]]; then
    echo "#!/bin/bash" > "$MODULE_FILE"
    echo "# Mock module for $module" >> "$MODULE_FILE"
    chmod +x "$MODULE_FILE"
  fi
done

echo "==== Testing default installation flow ===="
cd "$PROJECT_ROOT"
export TEST_MODE=1
export DEBUG=1

# Write inputs to a file for better control
INPUTS_FILE=$(mktemp)
cat > "$INPUTS_FILE" <<EOF
y
y
1
n
bash
EOF

# Test the default flow using the file as input
cat "$INPUTS_FILE" | ./install.sh --test --debug > /tmp/default_output.txt 2>&1
DEFAULT_RESULT=$?
echo "Default flow exit code: $DEFAULT_RESULT"

# Check for expected output strings
echo "Checking default flow output..."
if grep -q "Partitioning disk" /tmp/default_output.txt && 
   grep -q "Installing base system" /tmp/default_output.txt &&
   grep -q "No additional packages" /tmp/default_output.txt &&
   grep -q "Installation complete" /tmp/default_output.txt; then
  echo "✅ Default flow test PASSED - All expected strings found"
else
  echo "❌ Default flow test FAILED - Missing expected strings"
  echo "--- Output: ---"
  cat /tmp/default_output.txt
  exit 1
fi

echo "==== Testing custom packages installation flow ===="

# Write custom inputs to a file
CUSTOM_INPUTS_FILE=$(mktemp)
cat > "$CUSTOM_INPUTS_FILE" <<EOF
y
y
1
y
vim git firefox
zsh
EOF

# Test the custom packages flow
cat "$CUSTOM_INPUTS_FILE" | ./install.sh --test --debug > /tmp/custom_output.txt 2>&1
CUSTOM_RESULT=$?
echo "Custom flow exit code: $CUSTOM_RESULT"

# Check for expected output strings
echo "Checking custom flow output..."
if grep -q "Do you want to install additional packages" /tmp/custom_output.txt &&
   grep -q "Installing additional packages" /tmp/custom_output.txt &&
   grep -q "vim git firefox" /tmp/custom_output.txt &&
   grep -q "Setting up zsh" /tmp/custom_output.txt; then
  echo "✅ Custom packages flow test PASSED - All expected strings found"
else
  echo "❌ Custom packages flow test FAILED - Missing expected strings"
  echo "--- Output: ---"
  cat /tmp/custom_output.txt
  # Show specific missing strings
  for string in "Do you want to install additional packages" "Installing additional packages" "vim git firefox" "Setting up zsh"; do
    if grep -q "$string" /tmp/custom_output.txt; then
      echo "Found: $string"
    else
      echo "MISSING: $string"
    fi
  done
  exit 1
fi

echo "==== All tests passed! ===="
