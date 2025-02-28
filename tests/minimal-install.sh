#!/bin/bash
# Minimalist version of the installation script for testing

set -e

# Identify running context
if [[ $EUID -eq 0 ]]; then
  echo "Running as root (sudo)"
else
  echo "Running as normal user"
fi

echo "PATH=$PATH"
echo "TEST_MODE=$TEST_MODE"
echo "DEBUG=$DEBUG"
echo "PWD=$(pwd)"

# Set test mode if not already set
export TEST_MODE=${TEST_MODE:-1}
export DEBUG=${DEBUG:-1}

# Source the main install functions but don't run installation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Script directory: $SCRIPT_DIR"
echo "Project root: $PROJECT_ROOT"
echo "Install.sh exists: $(test -f "$PROJECT_ROOT/install.sh" && echo "Yes" || echo "No")"
ls -la "$PROJECT_ROOT"

# Create dummy modules if needed
mkdir -p "$PROJECT_ROOT/modules"
for module in checks disk filesystem network system user utils; do
  MODULE_FILE="$PROJECT_ROOT/modules/${module}.sh"
  if [[ ! -f "$MODULE_FILE" ]]; then
    echo "#!/bin/bash" > "$MODULE_FILE"
    echo "echo \"Mock $module module\"" >> "$MODULE_FILE" 
    chmod +x "$MODULE_FILE"
  fi
done

# Override functions that might cause issues in testing
function blockdev() {
  # Fixed version that avoids syntax errors
  if [[ "$1" == "--getsize64" ]]; then
    echo "10737418240" # 10GB
  else
    echo "MOCK: blockdev $*"
  fi
  return 0
}

function sgdisk() {
  echo "MOCK: sgdisk $*"
  return 0
}

function ping() {
  echo "MOCK: ping successful"
  return 0
}

# Source the script
source "$PROJECT_ROOT/install.sh"

echo "Script sourced successfully!"
echo "Now testing individual functions..."

# Test each function with proper error handling
echo "==== Testing create_disk_menu ===="
create_disk_menu || {
  echo "FAILED: create_disk_menu"
  exit 1
}
echo "SUCCESS: create_disk_menu"

echo "==== Testing verify_disk_space ===="
verify_disk_space || {
  echo "FAILED: verify_disk_space"
  exit 1
}
echo "SUCCESS: verify_disk_space"

echo "==== Testing wipe_partitions ===="
# Override prompt to always return success (yes)
prompt() {
  return 0
}
wipe_partitions || {
  echo "FAILED: wipe_partitions"
  exit 1
}
echo "SUCCESS: wipe_partitions"

echo "==== Testing create_partition_menu ===="
partition_choice=1 # Pre-set the choice to avoid prompt
create_partition_menu || {
  echo "FAILED: create_partition_menu"
  exit 1
}
echo "SUCCESS: create_partition_menu"

echo "==== Testing perform_partitioning ===="
perform_partitioning || {
  echo "FAILED: perform_partitioning" 
  exit 1
}
echo "SUCCESS: perform_partitioning"

echo "==== Testing install_base_system ===="
install_base_system || {
  echo "FAILED: install_base_system"
  exit 1
}
echo "SUCCESS: install_base_system"

echo "==== Testing setup_user_accounts ===="
# Create a temporary file with responses
cat > /tmp/responses.txt <<EOF
y
vim git
bash
EOF
setup_user_accounts < /tmp/responses.txt || {
  echo "FAILED: setup_user_accounts"
  exit 1
}
echo "SUCCESS: setup_user_accounts"

echo "All functions tested successfully!"
exit 0
