#!/bin/bash
# This script tests sourcing the install.sh script

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MOCK_DIR="$SCRIPT_DIR/integration/mocks"

# Create mocks directory if it doesn't exist
mkdir -p "$MOCK_DIR"

# Set environment
export PATH="$MOCK_DIR:$PATH"
export TEST_MODE=1
export DEBUG=1

# Create modules directory
mkdir -p "$ROOT_DIR/modules"

echo "===== TESTING SOURCE FUNCTIONALITY ====="
echo "ROOT_DIR: $ROOT_DIR"

# Define test function
run_source_test() {
    # Source the script first
    echo "Sourcing install.sh..."
    # shellcheck source=/dev/null
    source "$ROOT_DIR/install.sh"
    
    # Then run it with inputs
    echo "Running with test inputs..."
    # Run main function directly with inputs from heredoc
    {
        echo "y"  # Continue with BIOS
        echo "y"  # Erase disk
        echo "1"  # Partitioning scheme
        echo "y"  # Additional packages
        echo "vim htop"  # Package list
        echo "zsh"  # Shell choice
    } | main --test
    
    # Check if successful
    local result=$?
    if [[ $result -eq 0 ]]; then
        echo "Source test completed successfully!"
    else
        echo "Source test failed with exit code: $result"
    fi
    return $result
}

# Run the test
run_source_test
EXIT_CODE=$?

echo "===== SOURCE TEST COMPLETED WITH EXIT CODE: $EXIT_CODE ====="
exit $EXIT_CODE
