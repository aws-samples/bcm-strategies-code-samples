#/bin/bash

# Check for parameters
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <sourceServerID>"
    exit 1
fi

# Record start time
start_time=$(date +%s.%N)

# Create restore job
restore_job_arn=$(aws drs start-recovery --source-servers sourceServerID=$1 --region eu-west-1 |jq -r '.job.arn')

# Wait for restore to complete
while true; do
    status=$(aws drs describe-jobs --region eu-west-1 --query "items[?arn=='$restore_job_arn']" |jq -r .[0].participatingServers[0].launchStatus) \

    if [ "$status" == "LAUNCHED" ]; then
        echo "Restore job completed successfully!"
        
        # Get the targetInstanceId
        restore_job_id=$(echo "$restore_job_arn" | awk -F/ '{print $NF}' | cut -d'/' -f2)
        instance_id=$(aws drs describe-job-log-items --job-id $restore_job_id --region eu-west-1 |jq -r '.items | map(select(.event == "LAUNCH_END")) | .[0].eventData.targetInstanceID')
        
        break
    fi
    
    echo "Current status: $status. Waiting for completion..."
    sleep 5
done

# Get the instance IP address
instance_ip=$(aws ec2 describe-instances --region eu-west-1 --instance-ids $instance_id --query "Reservations[].Instances[].PublicIpAddress" --output text)

# Wait until the instance replies
echo "Waiting for instance to reply..."
until $(curl --output /dev/null --silent --head --max-time 1 --fail http://$instance_ip); do
    printf '.'
    sleep 1
done
printf "\n"

# Measure RTA
end_time=$(date +%s.%N)
elapsed_time=$(echo "$end_time - $start_time" | bc)
echo "RTA: $elapsed_time seconds"
