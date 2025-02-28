#!/bin/bash
# The most direct and simple test to verify installation flow

# Get directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MOCK_DIR="$SCRIPT_DIR/integration/mocks"

# Create mocks directory
mkdir -p "$MOCK_DIR"

# Create mock lsblk command
cat > "$MOCK_DIR/lsblk" <<'EOF'
#!/bin/bash
# Simple mock that only returns disk names
if [[ "$*" == *"-d -o NAME -n"* ]]; then
  echo "sda"
  echo "sdb"
else
  echo "NAME SIZE MODEL"
  echo "sda  20G  MOCK_DISK1"
  echo "sdb  40G  MOCK_DISK2"
fi
exit 0
EOF
chmod +x "$MOCK_DIR/lsblk"

# Create mock ping command
cat > "$MOCK_DIR/ping" <<'EOF'
#!/bin/bash
echo "MOCK: Ping successful"
exit 0
EOF
chmod +x "$MOCK_DIR/ping"

# Create mock pacstrap
cat > "$MOCK_DIR/pacstrap" <<'EOF'
#!/bin/bash
echo "MOCK: Running pacstrap with args: $*"
mkdir -p "$2/etc"
exit 0
EOF
chmod +x "$MOCK_DIR/pacstrap"

# Create empty modules directory
mkdir -p "$ROOT_DIR/modules"

# Set environment
export PATH="$MOCK_DIR:$PATH"
export TEST_MODE=1
export DEBUG=1

echo "====== RUNNING SIMPLIFIED TEST ======"
echo "Using PATH: $PATH"
echo "Mock directory: $MOCK_DIR"
echo "Found in PATH: $(which lsblk)"
echo "======================================"

# Run with heredoc input
cd "$ROOT_DIR"
chmod +x install.sh

./install.sh --test --debug <<EOF
y
y
1
y
vim htop firefox
zsh
EOF

RESULT=$?
echo "====== TEST COMPLETED WITH EXIT CODE: $RESULT ======"
exit $RESULT
