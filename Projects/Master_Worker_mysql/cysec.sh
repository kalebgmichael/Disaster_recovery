#!/bin/bash

# List of container names or IDs to monitor
containers=("mysql_master" "mysql_slave" "wordpress")

# Commands to run when a container is down
restart_commands() {
    container=$1
    echo "Restarting container: $container"
    docker restart "$container" || {
        echo "Failed to restart $container. Attempting to recreate it..."
        # Example: docker-compose up -d
        docker-compose up -d "$container"
    }
    echo "Container $container has been restarted."
}

# Log file for monitoring output
log_file="docker_monitor.log"

# Check interval in seconds
check_interval=30

echo "Starting Docker container monitor..." | tee -a "$log_file"
echo "Monitoring containers: ${containers[*]}" | tee -a "$log_file"
echo "------------------------------------------------------------" | tee -a "$log_file"

# Infinite monitoring loop
while true; do
    for container in "${containers[@]}"; do
        # Check if the container is running
        status=$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)

        if [[ "$status" == "true" ]]; then
            echo "$(date): $container is running." >> "$log_file"
        else
            echo "$(date): $container is DOWN!" | tee -a "$log_file"
            restart_commands "$container"
        fi
    done

    # Wait before the next check
    sleep "$check_interval"
done
