#!/bin/bash
set -x  # Enable debug output of commands

# Defining variables
AWSCLI_PATH='/usr/local/bin/aws'         # Path to aws CLI binary
INVENTORY_FILE='/etc/ansible/prod_hosts' # Path to Ansible inventory file
IPS_FILE='/etc/ansible/prod.lists'       # File to store private IP addresses
ASG_NAME='pmo-prod-asg'                  # Auto Scaling Group name to query
SSH_KEY_PATH='~/.ssh/id_rsa'             # SSH private key path for EC2 access
WAIT_TIME=20                             # Time to wait in seconds

# Function: fetch private IPs of instances in the ASG and save to IPS_FILE
find_ips() {
    $AWSCLI_PATH ec2 describe-instances \
    --filters "Name=tag:aws:autoscaling:groupName,Values=$ASG_NAME" \
    --query 'Reservations[*].Instances[*].NetworkInterfaces[*].PrivateIpAddress' \
    --output text > "$IPS_FILE"
}

# Function: update Ansible inventory file with the fetched IPs
update_inventory() {
    echo "[webservers]" > "$INVENTORY_FILE" 
    while IFS= read -r instance; do
        ssh-keyscan -H "$instance" >> ~/.ssh/known_hosts  # Add to known_hosts to avoid ssh prompt
        echo "$instance ansible_user=ec2-user" >> "$INVENTORY_FILE"
    done < "$IPS_FILE"
    echo "Inventory updated successfully"
}

# Function: wait for a fixed time before next operations
wait_for_seconds() {
    echo "Waiting for $WAIT_TIME seconds..."
    sleep "$WAIT_TIME"
}

# Function: check if Docker container is running on each instance,
# if not, ssh in and run a script to start the container
check_docker_container() {
    while IFS= read -r instance; do
        ssh -i "$SSH_KEY_PATH" ec2-user@"$instance" "docker ps | grep appContainer" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Container not running on $instance. Starting container..."
            ssh -i "$SSH_KEY_PATH" ec2-user@"$instance" "bash /home/ec2-user/scripts/script.sh"
        else
            echo "Container is running on $instance."
        fi
    done < "$IPS_FILE"
}

# Main execution function
main() {
    find_ips
    update_inventory
    wait_for_seconds
    check_docker_container
}

# Run main function
main

### End of script
