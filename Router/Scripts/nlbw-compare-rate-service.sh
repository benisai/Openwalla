#!/bin/sh

# Service name
SERVICE_NAME="nlbw-compare-rate-service.sh"

# Path to the main script
SCRIPT_PATH="/usr/bin/nlbw-compare-rate.sh"

# File to store the old stats
OLD_FILE="/tmp/nlbw_old.csv"
# File to store the current stats
CURRENT_FILE="/tmp/nlbw_current.csv"
# File to store the final compare output
OUTPUT_FILE="/tmp/nlbw_final_compare.txt"

# Start the service
start() {
    stop
    echo "Starting nlbw-compare-rate.sh service..."
    # Run the script in the background
    /bin/sh "$SCRIPT_PATH" &
    
    echo "Service started with PID: $!"
}

# Stop the service
stop() {
    echo "Stopping nlbw-compare-rate.sh service..."
    
    # Find the PIDs of the running process
    pids=$(ps | grep "[n]lbw-compare-rate.sh" | awk '{print $1}')
    
    # If PIDs are found, kill each one
    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill "$pid"
            echo "Stopped process with PID: $pid"
        done
    else
        echo "No running nlbw-compare-rate.sh process found."
    fi
}

# Restart the service
restart() {
    stop
    start
}

# Enable the service (link to startup directory)
enable() {
    echo "Enabling nlbw-compare-rate.sh service..."
    # Create symlink to startup directory
    ln -s /etc/init.d/nlbw-compare-rate-service.sh /etc/rc.d/S99nlbw-compare-rate-service.sh
    echo "Service enabled."
}

# Disable the service (remove symlink)
disable() {
    echo "Disabling nlbw-compare-rate.sh service..."
    rm -f /etc/rc.d/S99nlbw-compare-rate-service.sh
    echo "Service disabled."
}

# Status of the service
status() {
    pids=$(ps | grep "[n]lbw-compare-rate.sh" | awk '{print $1}')
    
    if [ -n "$pids" ]; then
        echo "nlbw-compare-rate.sh is running with PID: $pids"
    else
        echo "nlbw-compare-rate.sh is not running."
    fi
}

# Main logic for the service
case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    enable)
        enable
        ;;
    disable)
        disable
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|enable|disable|status}"
        exit 1
        ;;
esac
