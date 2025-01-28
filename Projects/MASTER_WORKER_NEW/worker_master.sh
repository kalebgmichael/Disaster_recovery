#!/bin/bash

# Define variables
NETWORK_NAME="custom_mysql_network_new"
MASTER_CONTAINER_NAME="mysql_master"
SLAVE_CONTAINER_NAME="mysql_slave"
WORDPRESS_CONTAINER_NAME="wordpress"
MASTER_PORT=3308
SLAVE_PORT=3307
WORDPRESS_PORT=8799
MASTER_DATA_DIR="./master_data/data"  # Data directory for master
SLAVE_DATA_DIR="./slave_data/data"   # Data directory for slave
MASTER_CONFIG_DIR="./master-config"
SLAVE_CONFIG_DIR="./slave-config"
MYSQL_ROOT_PASSWORD="root_password"
MYSQL_DATABASE="master_db"
MYSQL_USER="master_user"
MYSQL_PASSWORD="master_password"

# Check if the Docker network already exists, reuse it if it does, otherwise create it
if docker network inspect $NETWORK_NAME >/dev/null 2>&1; then
  echo "Docker network $NETWORK_NAME already exists. Reusing it."
else
  echo "Docker network $NETWORK_NAME does not exist. Creating it."
  docker network create $NETWORK_NAME
fi

# Create necessary directories
mkdir -p $MASTER_DATA_DIR $SLAVE_DATA_DIR $MASTER_CONFIG_DIR $SLAVE_CONFIG_DIR

# Create dynamic configuration for master
cat > "$MASTER_CONFIG_DIR/my.cnf" <<EOL
[mysqld]
server-id=1
log-bin=mysql-bin
binlog-do-db=master_db
EOL

# Create dynamic configuration for slave
cat > "$SLAVE_CONFIG_DIR/my.cnf" <<EOL
[mysqld]
server-id=2
relay-log=mysql-relay
read-only=1
EOL

# Ensure the configuration files exist in the specified directories
if [[ ! -f "$MASTER_CONFIG_DIR/my.cnf" ]]; then
  echo "Error: $MASTER_CONFIG_DIR/my.cnf not found."
  exit 1
fi

if [[ ! -f "$SLAVE_CONFIG_DIR/my.cnf" ]]; then
  echo "Error: $SLAVE_CONFIG_DIR/my.cnf not found."
  exit 1
fi

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

# Create and run the MySQL master container if it doesn't exist
if is_container_exists $MASTER_CONTAINER_NAME; then
  echo "Master container already exists. Skipping creation."
else
  echo "Running MySQL master container..."
  docker run -d \
    --name $MASTER_CONTAINER_NAME \
    --network $NETWORK_NAME \
    -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD \
    -e MYSQL_DATABASE=$MYSQL_DATABASE \
    -e MYSQL_USER=$MYSQL_USER \
    -e MYSQL_PASSWORD=$MYSQL_PASSWORD \
    -p $MASTER_PORT:3306 \
    -v $MASTER_DATA_DIR:/var/lib/mysql \
    -v $MASTER_CONFIG_DIR/my.cnf:/etc/mysql/my.cnf \
    mysql:5.7

  # Wait for the master container to initialize
  echo "Waiting for master to initialize..."
  sleep 20

  # Configure the master for replication
  docker exec -i $MASTER_CONTAINER_NAME mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
    CREATE USER 'replica_user'@'%' IDENTIFIED BY 'replica_password';
    GRANT REPLICATION SLAVE ON *.* TO 'replica_user'@'%';
    FLUSH PRIVILEGES;
    FLUSH TABLES WITH READ LOCK;
    SHOW MASTER STATUS\G" > master_status.txt

  # Extract the binlog and position for replication
  BINLOG_FILE=$(grep "File:" master_status.txt | awk '{print $2}')
  BINLOG_POSITION=$(grep "Position:" master_status.txt | awk '{print $2}')

  if [[ -z "$BINLOG_FILE" || -z "$BINLOG_POSITION" ]]; then
    echo "Error: Failed to extract binlog file or position from the master. Check the logs."
    cat master_status.txt
    exit 1
  fi

  echo "Master configured with File: $BINLOG_FILE and Position: $BINLOG_POSITION"
fi

# Create and run the MySQL slave container if it doesn't exist
if is_container_exists $SLAVE_CONTAINER_NAME; then
  echo "Slave container already exists. Skipping creation."
else
  echo "Running MySQL slave container..."
  docker run -d \
    --name $SLAVE_CONTAINER_NAME \
    --network $NETWORK_NAME \
    -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD \
    -e MYSQL_DATABASE=$MYSQL_DATABASE \
    -e MYSQL_USER=$MYSQL_USER \
    -e MYSQL_PASSWORD=$MYSQL_PASSWORD \
    -p $SLAVE_PORT:3306 \
    -v $SLAVE_DATA_DIR:/var/lib/mysql \
    -v $SLAVE_CONFIG_DIR/my.cnf:/etc/mysql/my.cnf \
    mysql:5.7

  # Wait for the slave container to initialize
  echo "Waiting for slave to initialize..."
  sleep 20

  # Configure the slave for replication
  docker exec -i $SLAVE_CONTAINER_NAME mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
    CHANGE MASTER TO
      MASTER_HOST='$MASTER_CONTAINER_NAME',
      MASTER_USER='replica_user',
      MASTER_PASSWORD='replica_password',
      MASTER_LOG_FILE='$BINLOG_FILE',
      MASTER_LOG_POS=$BINLOG_POSITION;
    START SLAVE;
    SHOW SLAVE STATUS\G"

  echo "Replication setup complete."
fi


# Check if the master container is running, if not, use slave as the database host
WORDPRESS_DB_HOST=$MASTER_CONTAINER_NAME
if ! is_container_running $MASTER_CONTAINER_NAME; then
  echo "Master container is not running, checking worker DB as the database."
  WORDPRESS_DB_HOST=$SLAVE_CONTAINER_NAME

    # Check if the WordPress container exists, and remove it if it does
    if is_container_exists $WORDPRESS_CONTAINER_NAME; then
    echo "Mater DB not working: checking WordPress container exists. Stopping and removing it..."
    docker rm -f $WORDPRESS_CONTAINER_NAME
    fi
    ## check if the worker db also works
    if ! is_container_running $SLAVE_CONTAINER_NAME; then
        echo "Worker and Master DB not working: exiting ..."
        ## restart both containers
        restart_mysql_container "$MASTER_CONTAINER_NAME" "$MASTER_DATA_DIR"
        restart_mysql_container "$SLAVE_CONTAINER_NAME" "$SLAVE_DATA_DIR"
    else

    # Run the WordPress container and worker db is working
    echo "Running WordPress container With Worker DB Since Master DB is down..."
    docker run -d \
    --name $WORDPRESS_CONTAINER_NAME \
    --network $NETWORK_NAME \
    -e WORDPRESS_DB_HOST=$WORDPRESS_DB_HOST:3306 \
    -e WORDPRESS_DB_NAME=$MYSQL_DATABASE \
    -e WORDPRESS_DB_USER=$MYSQL_USER \
    -e WORDPRESS_DB_PASSWORD=$MYSQL_PASSWORD \
    -p $WORDPRESS_PORT:80 \
    wordpress:latest

    echo "New WordPress with worker DB setup complete. Access it at http://localhost:$WORDPRESS_PORT"
    ## restart master after the worker has taken over
    restart_mysql_container "$MASTER_CONTAINER_NAME" "$MASTER_DATA_DIR"
    fi
else
    # master db working 
    # Check if the WordPress container exists
    if is_container_exists $WORDPRESS_CONTAINER_NAME; then
        echo "WordPress container exists"
        if ! is_container_running $SLAVE_CONTAINER_NAME; then

        ## restart worker db: since if master was off and is up again but worker is still down: it will avoid the rebuild of the wordpress container. 
        ## but if master db was down and is up again. toghether with the worker DB we will not have the poblem of rebuilding since the DB is always master DB
        ##configuration remains the same.
            # Call the function to restart the mysql_slave container with the values of the variables
            restart_mysql_container "$SLAVE_CONTAINER_NAME" "$SLAVE_DATA_DIR"
            echo "Slave container not running and Master container is running, using Master as the database."
            WORDPRESS_DB_HOST=$MASTER_CONTAINER_NAME
            echo "Worker DB not working: checking WordPress container exists. Stopping and removing it..."
            docker rm -f $WORDPRESS_CONTAINER_NAME

            # Run the WordPress container
            echo "Running WordPress container With Master DB Since worker DB is down..."
            docker run -d \
            --name $WORDPRESS_CONTAINER_NAME \
            --network $NETWORK_NAME \
            -e WORDPRESS_DB_HOST=$WORDPRESS_DB_HOST:3306 \
            -e WORDPRESS_DB_NAME=$MYSQL_DATABASE \
            -e WORDPRESS_DB_USER=$MYSQL_USER \
            -e WORDPRESS_DB_PASSWORD=$MYSQL_PASSWORD \
            -p $WORDPRESS_PORT:80 \
            wordpress:latest

            echo "New WordPress with Master DB setup complete. Access it at http://localhost:$WORDPRESS_PORT"

        else
        ## the master and worker DB are up and running 
            echo "WordPress is still up and running. Access it at http://localhost:$WORDPRESS_PORT"
        fi 
    else        
        # Run the WordPress container if both DB are up and running and the wordpress container does not exist
        echo "Running WordPress container for the first time with master DB..."
        docker run -d \
        --name $WORDPRESS_CONTAINER_NAME \
        --network $NETWORK_NAME \
        -e WORDPRESS_DB_HOST=$WORDPRESS_DB_HOST:3306 \
        -e WORDPRESS_DB_NAME=$MYSQL_DATABASE \
        -e WORDPRESS_DB_USER=$MYSQL_USER \
        -e WORDPRESS_DB_PASSWORD=$MYSQL_PASSWORD \
        -p $WORDPRESS_PORT:80 \
        wordpress:latest

        echo "WordPress setup complete. Access it at http://localhost:$WORDPRESS_PORT"
    fi
fi

