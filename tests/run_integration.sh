#!/bin/bash
# Direct test runner for integration tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create necessary directories
mkdir -p "$ROOT_DIR/modules"
mkdir -p "$SCRIPT_DIR/integration/mocks"

# Set up mock modules
for module in checks disk filesystem network system user utils; do
  echo "#!/bin/bash" > "$ROOT_DIR/modules/${module}.sh"
  echo "# Mock module for $module" >> "$ROOT_DIR/modules/${module}.sh"
  chmod +x "$ROOT_DIR/modules/${module}.sh"
done

# Set up mock commands
if [ ! -f "$SCRIPT_DIR/integration/mocks/lsblk" ]; then
  cat > "$SCRIPT_DIR/integration/mocks/lsblk" <<'EOF'
#!/bin/bash
if [[ "$*" == *"-d -o NAME -n"* ]]; then
  echo "sda"
  echo "sdb"
elif [[ "$*" == *"-d"* ]]; then
  echo "NAME SIZE MODEL"
  echo "sda  20G  MOCK_DISK1"
  echo "sdb  40G  MOCK_DISK2"
else
  echo "NAME SIZE MODEL"
  echo "sda  20G  MOCK_DISK1"
  echo "sdb  40G  MOCK_DISK2"
fi
exit 0
EOF
  chmod +x "$SCRIPT_DIR/integration/mocks/lsblk"
fi

if [ ! -f "$SCRIPT_DIR/integration/mocks/ping" ]; then
  cat > "$SCRIPT_DIR/integration/mocks/ping" <<'EOF'
#!/bin/bash
echo "MOCK: Ping successful"
exit 0
EOF
  chmod +x "$SCRIPT_DIR/integration/mocks/ping"
fi

if [ ! -f "$SCRIPT_DIR/integration/mocks/which" ]; then
  cat > "$SCRIPT_DIR/integration/mocks/which" <<'EOF'
#!/bin/bash
echo "/mock/bin/$1"
exit 0
EOF
  chmod +x "$SCRIPT_DIR/integration/mocks/which"
fi

# Make sure all mock commands are executable
find "$SCRIPT_DIR/integration/mocks" -type f -exec chmod +x {} \;

# Set environment variables
export PATH="$SCRIPT_DIR/integration/mocks:$PATH"
export TEST_MODE=1
export DEBUG=1

echo "================================================================="
echo "Running custom installation test"
echo "================================================================="
echo "Using PATH: $PATH"
echo "Running from: $(pwd)"
echo "Mock files:"
ls -la "$SCRIPT_DIR/integration/mocks/"
echo "================================================================="

# Make install.sh executable
chmod +x "$ROOT_DIR/install.sh"

# Run the test with input
cd "$ROOT_DIR"
./install.sh --test --debug <<INPUTS
1
y
1
y
vim git firefox
zsh
INPUTS

echo "================================================================="
echo "Test exit code: $?"
echo "================================================================="
