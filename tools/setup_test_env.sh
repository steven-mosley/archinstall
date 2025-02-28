#!/usr/bin/env bash

# Script to set up the testing environment for archinstall

set -e

# Initialize and update git submodules
git_setup_submodules() {
    echo "Setting up git submodules..."
    git submodule init
    git submodule update
    echo "Git submodules initialized successfully."
}

# Ensure bats-core is properly installed
setup_bats() {
    echo "Setting up bats testing framework..."
    if [ ! -d "bats-core" ] || [ ! -f "bats-core/bin/bats" ]; then
        if [ -d "bats-core" ]; then
            # Remove if exists but is incomplete
            rm -rf bats-core
        fi
        git submodule add https://github.com/bats-core/bats-core.git
    else
        echo "bats-core already initialized"
    fi

    # Make bats executable
    chmod +x bats-core/bin/bats
    echo "bats-core setup complete."
}

# Create tests directory if it doesn't exist
setup_test_dir() {
    if [ ! -d "tests" ]; then
        echo "Creating tests directory..."
        mkdir -p tests
        cp test_install.sh tests/
        echo "Tests directory created."
    else
        echo "Tests directory already exists."
    fi
}

# Main function
main() {
    echo "Setting up archinstall test environment..."
    git_setup_submodules
    setup_bats
    setup_test_dir
    echo "Test environment setup complete."
    echo "Run tests with: ./bats-core/bin/bats tests/"
}

# Run the script
main
