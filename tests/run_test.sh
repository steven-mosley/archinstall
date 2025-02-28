#!/bin/bash
# Universal test script that works with or without sudo

set -e  # Exit on error

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create global mock directory
MOCK_DIR="$SCRIPT_DIR/mocks"
mkdir -p "$MOCK_DIR"

# Create essential mock commands
cat > "$MOCK_DIR/lsblk" <<'EOF'
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
chmod +x "$MOCK_DIR/lsblk"

cat > "$MOCK_DIR/ping" <<'EOF'
#!/bin/bash
echo "MOCK: Ping successful"
exit 0
EOF
chmod +x "$MOCK_DIR/ping"

cat > "$MOCK_DIR/pacstrap" <<'EOF'
#!/bin/bash
echo "MOCK: pacstrap $*"
mkdir -p "$2/etc"
exit 0
EOF
chmod +x "$MOCK_DIR/pacstrap"

cat > "$MOCK_DIR/sgdisk" <<'EOF'
#!/bin/bash
echo "MOCK: sgdisk $*"
exit 0
EOF
chmod +x "$MOCK_DIR/sgdisk"

cat > "$MOCK_DIR/reflector" <<'EOF'
#!/bin/bash
echo "MOCK: reflector $*"
exit 0
EOF
chmod +x "$MOCK_DIR/reflector"

cat > "$MOCK_DIR/blockdev" <<'EOF'
#!/bin/bash
echo "10737418240"
exit 0
EOF
chmod +x "$MOCK_DIR/blockdev"

# Make sure ALL mock scripts are executable
find "$MOCK_DIR" -type f -exec chmod +x {} \;

# Create module files
mkdir -p "$ROOT_DIR/modules"
for module in checks disk filesystem network system user utils; do
  MODULE_FILE="$ROOT_DIR/modules/${module}.sh"
  echo "#!/bin/bash" > "$MODULE_FILE"
  echo "# Mock module for testing" >> "$MODULE_FILE"
  chmod +x "$MODULE_FILE"
done

# Make install.sh executable
chmod +x "$ROOT_DIR/install.sh"

# Run as non-root or root
RUN_AS_ROOT=0
if [[ "$1" == "--root" ]]; then
  RUN_AS_ROOT=1
  shift
fi

# Prepare test environment
echo "========== TEST SETUP =========="
echo "Project root: $ROOT_DIR"
echo "Mock dir: $MOCK_DIR"
echo "PATH: $MOCK_DIR:$PATH"
echo "Running as root: $RUN_AS_ROOT"
echo "==============================="

# Function to run the test
run_the_test() {
  # Set environment
  export PATH="$MOCK_DIR:$PATH"
  export TEST_MODE=1
  export DEBUG=1
  
  # Run the install.sh script with specific inputs
  cd "$ROOT_DIR"
  ./install.sh --test --debug <<INPUT
y
y
1
y
vim htop firefox
zsh
INPUT
}

# Run either directly or with sudo
if [[ $RUN_AS_ROOT -eq 1 ]]; then
  # Create a temporary script to run as root
  TMP_SCRIPT=$(mktemp)
  cat > "$TMP_SCRIPT" <<EOF
#!/bin/bash
export PATH="$MOCK_DIR:\$PATH"
export TEST_MODE=1
export DEBUG=1
cd "$ROOT_DIR"
./install.sh --test --debug <<INPUT
y
y
1
y
vim htop firefox
zsh
INPUT
EOF
  chmod +x "$TMP_SCRIPT"
  
  # Run with sudo
  sudo bash "$TMP_SCRIPT"
  RESULT=$?
  rm -f "$TMP_SCRIPT"
else
  # Run directly
  run_the_test
  RESULT=$?
fi

# Output result
echo "==============================="
echo "Test completed with exit code: $RESULT"
echo "==============================="

exit $RESULT
