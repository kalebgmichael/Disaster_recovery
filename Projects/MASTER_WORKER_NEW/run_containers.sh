#!/bin/bash

# Define variables
NETWORK_NAME="custom-network"
MASTER_CONTAINER="mysql_master"
SLAVE_CONTAINER="mysql_slave"
WORDPRESS_CONTAINER="wordpress"
UPTIME_KUMA_CONTAINER="uptime-kuma"

# Create the custom Docker network if it doesn't exist
if ! docker network ls | grep -q $NETWORK_NAME; then
  echo "Creating Docker network: $NETWORK_NAME"
  docker network create $NETWORK_NAME
else
  echo "Docker network $NETWORK_NAME already exists."
fi

# Run the MySQL Master container
echo "Starting MySQL Master container..."
docker run -d \
  --name $MASTER_CONTAINER \
  --network $NETWORK_NAME \
  -p 3308:3306 \
  -e MYSQL_ROOT_PASSWORD=root_password \
  -e MYSQL_DATABASE=master_db \
  -e MYSQL_USER=master_user \
  -e MYSQL_PASSWORD=master_password \
  -v $(pwd)/master_data:/var/lib/mysql \
  -v $(pwd)/master-config:/etc/mysql/conf.d \
  mysql:5.7

# Run the MySQL Slave container
echo "Starting MySQL Slave container..."
docker run -d \
  --name $SLAVE_CONTAINER \
  --network $NETWORK_NAME \
  -p 3307:3306 \
  -e MYSQL_ROOT_PASSWORD=root_password \
  -e MYSQL_DATABASE=master_db \
  -e MYSQL_USER=master_user \
  -e MYSQL_PASSWORD=master_password \
  -v $(pwd)/slave_data:/var/lib/mysql \
  -v $(pwd)/slave-config:/etc/mysql/conf.d \
  mysql:5.7

echo "Starting WordPress container..."

# Run health check script in the background
# bash health-check.sh &

# Run the WordPress container
docker run -d \
  --name $WORDPRESS_CONTAINER \
  --network $NETWORK_NAME \
  -p 8799:80 \
  -e WORDPRESS_DB_HOST=mysql_master:3306 \
  -e WORDPRESS_DB_NAME=master_db \
  -e WORDPRESS_DB_USER=master_user \
  -e WORDPRESS_DB_PASSWORD=master_password \
  wordpress:latest


# Run the Uptime Kuma container
echo "Starting Uptime Kuma container..."
docker run -d \
  --name $UPTIME_KUMA_CONTAINER \
  --network $NETWORK_NAME \
  -p 3010:3001 \
  -v uptime-kuma:/app/data \
  -v /var/run/docker.sock:/var/run/docker.sock \
  louislam/uptime-kuma:1

echo "All containers started successfully!"

# Optional: Check container statuses
echo "Container statuses:"
docker ps
