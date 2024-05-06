#/bin/bash

# Check for parameters
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <recovery point> <recovery iam role>"
    exit 1
fi

# Record start time
start_time=$(date +%s.%N)

# Get default vpc
default_vpc=$(aws ec2 describe-vpcs --region eu-west-1 --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)

# Create restore job
restore_job_id=$(aws backup start-restore-job \
    --region eu-west-1 \
    --idempotency-token $(uuidgen) \
    --recovery-point-arn $1 \
    --iam-role-arn $2 \
    --metadata '{"VpcId": "$default_vpc","Placement": "{\"AvailabilityZone\":\"eu-west-1b\"}","InstanceType": "m6g.xlarge"}' \
    |jq -r '.RestoreJobId')

echo "Restore Job started with id $restore_job_id"

# Wait for restore to complete
while true; do
    status=$(aws backup describe-restore-job --region eu-west-1 --restore-job-id ${restore_job_id//[^a-zA-Z0-9\-]/} \
        --query 'Status' --output text)
    
    if [ "$status" == "COMPLETED" ]; then
        echo "Restore job completed successfully!"
        
        # Get the CreatedResourceId
        created_resource_id=$(aws backup describe-restore-job --region eu-west-1 --restore-job-id ${restore_job_id//[^a-zA-Z0-9\-]/} \
            --query 'CreatedResourceArn' --output text | cut -d'/' -f2)
        
        break
    fi
    
    echo "Current status: $status. Waiting for completion..."
    sleep 5
done

# Get the instance ID from the CreatedResourceId
instance_id=$(echo "$created_resource_id" | awk -F/ '{print $NF}' | cut -d'/' -f2)

# Get the instance IP address
instance_ip=$(aws ec2 describe-instances --region eu-west-1 --instance-ids $instance_id --query "Reservations[].Instances[].PublicIpAddress" --output text)

# Wait until the instance replies
echo "Waiting for the application to reply..."
until $(curl --output /dev/null --silent --head --max-time 1 --fail http://$instance_ip); do
    printf '.'
    sleep 1
done
printf "\n"

# Measure RTA
end_time=$(date +%s.%N)
elapsed_time=$(echo "$end_time - $start_time" | bc)
echo "RTA: $elapsed_time seconds"
