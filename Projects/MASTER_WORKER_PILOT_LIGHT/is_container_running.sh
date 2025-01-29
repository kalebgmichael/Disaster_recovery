#!/bin/bash

# Variables
CONTAINER_NAME="mysql_worker"

# # Function to check if a container exists (running or stopped)
# is_container_exists() {
#   container_id=$(docker ps -a -q -f name="$1")
#   if [ -n "$container_id" ]; then
#     return 0  # Container exists
#   else
#     return 1  # Container doesn't exist
#   fi
# }

# # Function to check if a container is running (exists and running)
# is_container_running() {
#   container_id=$(docker ps -q -f "name=$1")
#   if [ -n "$container_id" ]; then
#     return 0  # Container is running
#   else
#     return 1  # Container doesn't exist or is stopped
#   fi
# }

# # Create and run the MySQL master container if it doesn't exist
# if is_container_running $CONTAINER_NAME; then
#   echo "Master container is already running. Skipping creation."
# elif is_container_exists $CONTAINER_NAME; then
#   echo "Master container exists but is not running. Starting it..."
#   docker start $CONTAINER_NAME
# else
#   echo "Running MySQL master container..."
# fi 

#!/bin/bash

# Define the container name and data directory
CONTAINER_NAME="mysql_worker"
WORKER_DATA_DIR="./worker_data/data"

# Function to restart the MySQL container by container ID and remove mysql.sock
restart_mysql_container() {
  local container_name="$1"
  local data_dir="$2"

  # Ensure the container name and data directory are provided
  if [ -z "$container_name" ] || [ -z "$data_dir" ]; then
    echo "Error: Container name and data directory must be provided."
    echo "Usage: restart_mysql_container <container_name> <data_dir>"
    return 1
  fi

  # Retrieve the container ID for the given container name
  container_id=$(docker ps -a -q -f name="^${container_name}$")

  if [ -n "$container_id" ]; then
    echo "Restarting $container_name with container ID: $container_id..."
    
    # Stop the container if it's running
    if docker ps -q -f "id=$container_id" >/dev/null 2>&1; then
      echo "Stopping the container..."
      docker stop $container_id
    fi

    # Remove the mysql.sock file from the provided data directory
    if [ -e "$data_dir/mysql.sock" ]; then
      echo "Removing mysql.sock file from $data_dir..."
      rm -f "$data_dir/mysql.sock"
      echo "mysql.sock file removed."
    else
      echo "No mysql.sock file found in $data_dir. Skipping removal."
    fi

    # Restart the container
    echo "Starting the container..."
    docker start $container_id
    echo "$container_name container restarted successfully."
  else
    echo "No container found for $container_name. Ensure it exists."
    return 1
  fi
}

# Call the function to restart the mysql_slave container with the values of the variables
restart_mysql_container "$CONTAINER_NAME" "$WORKER_DATA_DIR"



