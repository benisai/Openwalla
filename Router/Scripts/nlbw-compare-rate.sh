#!/bin/sh

# File to store the old stats
OLD_FILE="/tmp/nlbw_old.csv"
# File to store the current stats
CURRENT_FILE="/tmp/nlbw_current.csv"
# File to store the final compare output
OUTPUT_FILE="/tmp/nlbw_final_compare.txt"

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

            # Output the differences to the file
            echo "TIME: $(date) | MAC: $mac | IP: $ip | RX Diff: $rx_diff bytes | TX Diff: $tx_diff bytes" >> "$OUTPUT_FILE"
        else
            echo "TIME: $(date) | MAC: $mac | IP: $ip | No previous data available." >> "$OUTPUT_FILE"
        fi
    done < "$CURRENT_FILE"
}

# Function to update the old file with the current data
update_old_file() {
    cp "$CURRENT_FILE" "$OLD_FILE"
}

# Main loop to run every 15 seconds
while true; do
    # Clear the previous output file
    > "$OUTPUT_FILE"

    # Collect current stats
    collect_nlbw_stats

    # Calculate differences and write to the output file
    calculate_difference

    # Update the old stats file with the current stats
    update_old_file

    # Sleep for 15 seconds before running again
    sleep 15
done

