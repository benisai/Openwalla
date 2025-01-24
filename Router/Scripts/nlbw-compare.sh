#!/bin/sh /etc/rc.common

# Script name and description
START=99
STOP=10
USE_PROCD=1

# Define the service name
SERVICE_NAME="nlbw-compare"

# File to store the old stats
OLD_FILE="/tmp/nlbw_old.csv"
CURRENT_FILE="/tmp/nlbw_current.csv"

# Function to collect nlbwmon stats and export to a file
collect_nlbw_stats() {
    nlbw -c csv -g ip,mac -o ip | tr -d '"' | tail -n +2 > "$CURRENT_FILE"
}

# Function to calculate differences in rx_bytes and tx_bytes
calculate_difference() {
    while read -r line; do
        mac=$(echo "$line" | awk '{print $1}')
        ip=$(echo "$line" | awk '{print $2}')
        rx_bytes_current=$(echo "$line" | awk '{print $4}')
        tx_bytes_current=$(echo "$line" | awk '{print $6}')

        # Find the matching MAC from the old file
        old_line=$(grep "$mac" "$OLD_FILE")
        if [ -n "$old_line" ]; then
            rx_bytes_old=$(echo "$old_line" | awk '{print $4}')
            tx_bytes_old=$(echo "$old_line" | awk '{print $6}')
            
            # Calculate the differences
            rx_diff=$((rx_bytes_current - rx_bytes_old))
            tx_diff=$((tx_bytes_current - tx_bytes_old))
            
            # Display the differences
            logger -t "$SERVICE_NAME" "MAC: $mac | IP: $ip | RX Diff: $rx_diff bytes | TX Diff: $tx_diff bytes"
        else
            logger -t "$SERVICE_NAME" "MAC: $mac | IP: $ip | No previous data available."
        fi
    done < "$CURRENT_FILE"
}

# Function to update the old file with the current data
update_old_file() {
    cp "$CURRENT_FILE" "$OLD_FILE"
}

# Service Start Function
start() {
    # Run the script as a background process
    while true; do
        collect_nlbw_stats
        calculate_difference
        update_old_file
        sleep 30
    done &
}

# Service Stop Function
stop() {
    # Stop the running background process
    killall -9 nlbw-compare.sh
}
