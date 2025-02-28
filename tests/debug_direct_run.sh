#!/bin/bash
# Debug version of the direct run test with more verbose output

# Do not exit on error so we can see what's happening
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==== DEBUG DIAGNOSTIC INFO ===="
echo "Running from: $(pwd)"
echo "Script directory: $SCRIPT_DIR"
echo "Project root: $PROJECT_ROOT"
ls -la "$PROJECT_ROOT"
echo "============================"

echo "==== Setting up environment ===="
# Setup mocks directory and include in PATH
mkdir -p "$SCRIPT_DIR/integration/mocks"
export PATH="$SCRIPT_DIR/integration/mocks:$PATH"

echo "Checking for mock commands:"
find "$SCRIPT_DIR/integration/mocks" -type f | sort
echo

echo "Making mock commands executable..."
find "$SCRIPT_DIR/integration/mocks" -type f -exec chmod +x {} \;

echo "Testing mocks..."
which lsblk
lsblk -d -o NAME -n

# Create module files if they don't exist
echo "Setting up module files..."
mkdir -p "$PROJECT_ROOT/modules"
for module in checks disk filesystem network system user utils; do
  MODULE_FILE="$PROJECT_ROOT/modules/${module}.sh"
  if [[ ! -f "$MODULE_FILE" ]]; then
    echo "#!/bin/bash" > "$MODULE_FILE"
    echo "# Mock module for $module created by debug_direct_run.sh" >> "$MODULE_FILE"
    chmod +x "$MODULE_FILE"
    echo "Created module: $MODULE_FILE"
  else
    echo "Module already exists: $MODULE_FILE"
  fi
done
ls -la "$PROJECT_ROOT/modules"

echo "==== Testing direct run with default flow ===="
cd "$PROJECT_ROOT"
export TEST_MODE=1
export DEBUG=1

echo "Preparing input for default flow..."
cat > /tmp/default_input.txt <<EOF
y
y
1
n
bash
EOF

echo "Running default flow with input:"
cat /tmp/default_input.txt
echo "----------------------------------------"

# Run directly with all output visible (no redirection)
cat /tmp/default_input.txt | bash ./install.sh --test --debug
DEFAULT_RESULT=$?

echo "----------------------------------------"
echo "Default flow completed with exit code: $DEFAULT_RESULT"

if [ $DEFAULT_RESULT -eq 0 ]; then
  echo "✅ Default flow test succeeded"
else
  echo "❌ Default flow test failed with exit code $DEFAULT_RESULT"
fi

echo "==== Testing custom packages installation flow ===="

echo "Preparing input for custom flow..."
cat > /tmp/custom_input.txt <<EOF
y
y
1
y
vim git firefox
zsh
EOF

echo "Running custom flow with input:"
cat /tmp/custom_input.txt
echo "----------------------------------------"

# Run directly with all output visible
cat /tmp/custom_input.txt | bash ./install.sh --test --debug
CUSTOM_RESULT=$?

echo "----------------------------------------"
echo "Custom flow completed with exit code: $CUSTOM_RESULT"

if [ $CUSTOM_RESULT -eq 0 ]; then
  echo "✅ Custom flow test succeeded"
else
  echo "❌ Custom flow test failed with exit code $CUSTOM_RESULT"
fi

echo "==== Test run complete ===="
