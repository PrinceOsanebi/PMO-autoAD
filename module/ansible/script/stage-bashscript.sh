#!/bin/bash
set -euo pipefail
set -x  # Enable debug output for Jenkins logs

#  Configurations 
AWSCLI_PATH='/usr/local/bin/aws'
INVENTORY_FILE='/etc/ansible/stage_hosts'
IPS_FILE='/etc/ansible/stage.lists'
ASG_NAME='pmo-stage-asg'
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
WAIT_TIME=20
DEPLOYMENT_PLAYBOOK="/etc/ansible/deployment.yml"

# Fetch instance private IPs from the ASG 
find_ips() {
    $AWSCLI_PATH ec2 describe-instances \
      --filters "Name=tag:aws:autoscaling:groupName,Values=$ASG_NAME" \
      --query 'Reservations[*].Instances[*].PrivateIpAddress' \
      --output text > "$IPS_FILE"
}

#  Populate dynamic Ansible inventory file 
update_inventory() {
    echo "[webservers]" > "$INVENTORY_FILE"
    while IFS= read -r instance; do
        ssh-keyscan -H "$instance" >> ~/.ssh/known_hosts 2>/dev/null
        echo "$instance ansible_user=ec2-user" >> "$INVENTORY_FILE"
    done < "$IPS_FILE"
}

#  Wait for instance readiness 
wait_for_seconds() {
    echo "Waiting $WAIT_TIME seconds for EC2 readiness..."
    sleep "$WAIT_TIME"
}

# Ensure docker container is running or bootstrap it 
check_docker_container() {
    while IFS= read -r instance; do
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" ec2-user@"$instance" "docker ps | grep appContainer" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Starting container on $instance"
            ssh -i "$SSH_KEY_PATH" ec2-user@"$instance" "bash /home/ec2-user/scripts/script.sh"
        fi
    done < "$IPS_FILE"
}

# Run Ansible playbook for blue-green deployment 
run_ansible_playbook() {
    ansible-playbook -i "$INVENTORY_FILE" "$DEPLOYMENT_PLAYBOOK"
}

# Main Flow 
main() {
    find_ips
    update_inventory
    wait_for_seconds
    check_docker_container
    run_ansible_playbook
}

main
