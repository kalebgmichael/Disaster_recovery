#!/bin/bash

# Define variables
ORIGINAL_COMPOSE_DIR=$(pwd)                     # Current directory with the docker-compose.yml
NEW_COMPOSE_DIR="/home/cnit/Desktop/CNIT_WORK/sextet/Projects/SEXTET_NEW_BACKUP"         # Target directory for the new deployment
OLD_WORDPRESS_VOLUME="./wordpress_data"
OLD_DB_VOLUME="./db_data_1"
NEW_WORDPRESS_VOLUME="$NEW_COMPOSE_DIR/wordpress_data"
NEW_DB_VOLUME="$NEW_COMPOSE_DIR/db_data_1"
EXCLUDE_FILE="mysql.sock"
CONTAINERS_NAME=("wordpress_container" "mysql_container")


# # Step 1: Start containers in the original location to ensure the volumes are populated
# echo "Starting containers in the original location to ensure volumes are ready..."
# docker-compose up -d

# Function to check if a container exists (running or stopped)
is_container_exists() {
  container_id=$(docker ps -a -q -f name="$1")
  if [ -n "$container_id" ]; then
    return 0  # Container exists
  else
    return 1  # Container doesn't exist
  fi
}


# Function to check if a container is running (exists and running)
is_container_running() {
  container_id=$(docker ps -q -f "name=$1")
  if [ -n "$container_id" ]; then
    return 0  # Container is running
  else
    return 1  # Container doesn't exist or is stopped
  fi
}

for i in "${!CONTAINERS_NAME[@]}"; do
      WORDPRESS_NAME=${CONTAINERS_NAME[$i]}
    ## check if the worker db also works
    if ! is_container_running $WORDPRESS_NAME; then
      # Step 3: Copy volumes to the new location
        echo "Copying volumes to the new location..."
        mkdir -p "$NEW_WORDPRESS_VOLUME" "$NEW_DB_VOLUME"

        # Copy WordPress volume
        rsync -av --exclude="$EXCLUDE_FILE" "$OLD_WORDPRESS_VOLUME/" "$NEW_WORDPRESS_VOLUME/"
        # Copy DB volume
        rsync -av --exclude="$EXCLUDE_FILE" "$OLD_DB_VOLUME/" "$NEW_DB_VOLUME/"

        # # Wait for containers to initialize
        # echo "Waiting for containers to initialize..."
        # sleep 10

        # Step 2: Stop the containers in the original location (optional)
        echo "Stopping containers in the original location..."
        docker-compose down

        # # Wait for containers to initialize
        # echo "Waiting for containers to initialize..."
        sleep 30


        # Step 4: Deploy containers in the new location using the copied volumes
        echo "Deploying containers in the new location..."
        cd "$NEW_COMPOSE_DIR" || exit
        docker-compose up -d

        # Step 5: Return to the original directory
        cd "$ORIGINAL_COMPOSE_DIR" || exit

        echo "Operation completed successfully. Containers are now running in the new location with the copied volumes."  
    fi 
  done 

# Wait for containers to initialize
# echo "Waiting for containers to initialize..."
# sleep 30
# # Step 3: Copy volumes to the new location
# echo "Copying volumes to the new location..."
# mkdir -p "$NEW_WORDPRESS_VOLUME" "$NEW_DB_VOLUME"

# # Copy WordPress volume
# rsync -av --exclude="$EXCLUDE_FILE" "$OLD_WORDPRESS_VOLUME/" "$NEW_WORDPRESS_VOLUME/"
# # Copy DB volume
# rsync -av --exclude="$EXCLUDE_FILE" "$OLD_DB_VOLUME/" "$NEW_DB_VOLUME/"

# # # Wait for containers to initialize
# # echo "Waiting for containers to initialize..."
# # sleep 10

# # Step 2: Stop the containers in the original location (optional)
# echo "Stopping containers in the original location..."
# docker-compose down

# # # Wait for containers to initialize
# # echo "Waiting for containers to initialize..."
# sleep 30


# # Step 4: Deploy containers in the new location using the copied volumes
# echo "Deploying containers in the new location..."
# cd "$NEW_COMPOSE_DIR" || exit
# docker-compose up -d

# # Step 5: Return to the original directory
# cd "$ORIGINAL_COMPOSE_DIR" || exit

# echo "Operation completed successfully. Containers are now running in the new location with the copied volumes."