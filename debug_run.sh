#!/bin/bash
# Script to run the install script with debug tracing

set -x  # Enable command tracing
export TEST_MODE=1
export DEBUG=1

# Create necessary directories
mkdir -p modules

# Create basic module files if they don't exist
for module in checks disk filesystem network system user utils; do
  if [ ! -f "modules/${module}.sh" ]; then
    echo "#!/bin/bash" > "modules/${module}.sh"
    echo "echo \"Mock ${module} module loaded\"" >> "modules/${module}.sh"
    chmod +x "modules/${module}.sh"
  fi
done

# Run the install script with debug output
./install.sh --test --debug

echo "Exit code: $?"
