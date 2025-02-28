#!/bin/bash
# Trace execution of the install script

# Enable command echoing for full visibility of what's running
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create directory for execution logs
mkdir -p "/tmp/archinstall_trace"
TRACE_LOG="/tmp/archinstall_trace/execution.log"

# Prepare mock environment
mkdir -p "$SCRIPT_DIR/integration/mocks"
export PATH="$SCRIPT_DIR/integration/mocks:$PATH"
chmod +x "$SCRIPT_DIR/integration/mocks/"* 2>/dev/null

# Set up debug flags
export TEST_MODE=1
export DEBUG=1

# Create DIY expect script with timeout to prevent hanging
(
  # Send inputs with delay to ensure they're properly processed
  sleep 0.5
  echo "y"  # BIOS question
  sleep 0.5
  echo "y"  # Disk wiping
  sleep 0.5
  echo "1"  # Partitioning scheme
  sleep 0.5
  echo "y"  # Install packages question
  sleep 0.5
  echo "vim git"  # Package list
  sleep 0.5
  echo "zsh"  # Shell choice
) | (
  # Run the script with tracing, saving both stdout and stderr
  cd "$PROJECT_ROOT"
  bash -x ./install.sh --test --debug 2>&1 | tee "$TRACE_LOG"
)

EXIT_CODE=${PIPESTATUS[0]}
echo "Exit code: $EXIT_CODE"

# Show the last few commands that ran before failure if there was an error
if [[ $EXIT_CODE -ne 0 ]]; then
  echo "Last 50 lines of execution before failure:"
  tail -n 50 "$TRACE_LOG"
  
  # Extract error messages
  echo "Error messages found:"
  grep -E '\[ERROR\]|error:|failed|cannot|not found' "$TRACE_LOG" | tail -n 10
fi

echo "Complete trace log is available at: $TRACE_LOG"
