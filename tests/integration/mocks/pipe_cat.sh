#!/bin/bash
# Helper script to create a FIFO for piping and showing input during tests

# Create a named pipe
PIPE=$(mktemp -u)
mkfifo "$PIPE"

# Read standard input and tee it to both the named pipe and standard output
tee "$PIPE" &
TEE_PID=$!

# Wait for a moment to ensure tee starts reading
sleep 0.1

# Run the target command with the named pipe as its input
"$@" < "$PIPE"
EXIT_CODE=$?

# Wait for tee to finish
wait $TEE_PID

# Clean up
rm -f "$PIPE"

exit $EXIT_CODE
