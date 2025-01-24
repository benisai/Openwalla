#!/bin/sh /etc/rc.common

# Start and stop script for the nlbw-compare.sh service

START=99
STOP=10

# Path to the nlbw-compare.sh script
SCRIPT_PATH="/usr/bin/nlbw-compare.sh"

start() {
    echo "Starting nlbw-compare.sh service..."
    # Ensure the script is executable
    chmod +x $SCRIPT_PATH
    # Run the script in the background
    $SCRIPT_PATH &
}

stop() {
    echo "Stopping nlbw-compare.sh service..."

    # Find the PIDs of the running process
    pids=$(ps | grep "[n]lbw-compare.sh" | awk '{print $1}')

    # If PIDs are found, kill each one
    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill "$pid"
            echo "Stopped process with PID: $pid"
        done
    else
        echo "No running nlbw-compare.sh process found."
    fi
}
