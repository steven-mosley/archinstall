#!/bin/bash
# Debug script for the integration tests

set -e

# Get absolute path to root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Print current environment
echo "====== TEST ENVIRONMENT ======"
echo "Working directory: $(pwd)"
echo "Project root: $PROJECT_ROOT"
echo "Script directory: $SCRIPT_DIR"
echo "USER: $(whoami)"
echo "HOME: $HOME"

# Set up environment
export TEST_MODE=1
export DEBUG=1

# Set up PATH to use our mock commands
export PATH="$SCRIPT_DIR/mocks:$PATH"

# Make all mock commands executable
echo "Making mock commands executable..."
find "$SCRIPT_DIR/mocks" -type f | while read -r file; do
  chmod +x "$file"
  echo "  - $file"
done

# Create necessary directories
mkdir -p "$PROJECT_ROOT/modules"
mkdir -p /tmp/mnt

# Create module files if they don't exist
for module in checks disk filesystem network system user utils; do
  MODULE_FILE="$PROJECT_ROOT/modules/${module}.sh"
  if [[ ! -f "$MODULE_FILE" ]]; then
    echo "#!/bin/bash" > "$MODULE_FILE"
    echo "# Mock module for $module" >> "$MODULE_FILE"
    chmod +x "$MODULE_FILE"
  fi
done

# Print a list of files in the project root
echo -e "\n====== PROJECT FILES ======"
ls -la "$PROJECT_ROOT"

echo -e "\n====== RUNNING TEST WITH VERBOSE DEBUG ======"
cd "$PROJECT_ROOT"

# Enable shell debugging
set -x

# Run the installation script with detailed debug output
./install.sh --test --debug <<EOF
y
y
1
y
vim git firefox
zsh
EOF

EXIT_CODE=$?

# Disable shell debugging
set +x

echo -e "\n====== TEST COMPLETED WITH EXIT CODE: $EXIT_CODE ======"
exit $EXIT_CODE
