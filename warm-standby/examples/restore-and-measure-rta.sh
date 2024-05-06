#/bin/bash

# Check for parameters
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <StandbyServerIP>"
    exit 1
fi

# Record start time
start_time=$(date +%s.%N)

# Wait until the instance replies
echo "Waiting for instance to reply..."
until $(curl --output /dev/null --silent --head --max-time 1 --fail http://$1); do
    printf '.'
    sleep 1
done
printf "\n"

# Measure RTA
end_time=$(date +%s.%N)
elapsed_time=$(echo "$end_time - $start_time" | bc)
echo "RTA: $elapsed_time seconds\n"

echo "To stop the database replication, connect to the Standby RDS Instance and run 'call mysql.rds_stop_replication;'"
