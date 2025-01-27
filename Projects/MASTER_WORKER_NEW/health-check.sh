# health-check.sh
while true; do
    if nc -z localhost 3308; then
        export DB_HOST="mysql_master:3306"
    elif nc -z localhost 3307; then
        export DB_HOST="mysql_slave:3306"
    else
        echo "No available database host!"
    fi
    sleep 5
done
