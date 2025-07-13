locals {
  ansible_userdata = <<-EOF
    #!/bin/bash
    set -e

    # Update instance and install dependencies
    sudo yum update -y
    sudo yum install -y wget unzip dnf

    # Disable SSH StrictHostKeyChecking globally for ec2-user
    echo "StrictHostKeyChecking no" | sudo tee -a /etc/ssh/ssh_config

    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    sudo ln -svf /usr/local/bin/aws /usr/bin/aws

    # Install Ansible Core
    sudo dnf install -y ansible-core

    # Create .ssh directory if it doesn't exist and set proper permissions
    sudo mkdir -p /home/ec2-user/.ssh
    echo '${var.private_key}' | sudo tee /home/ec2-user/.ssh/id_rsa > /dev/null
    sudo chown ec2-user:ec2-user /home/ec2-user/.ssh/id_rsa
    sudo chmod 400 /home/ec2-user/.ssh/id_rsa

    # Pull Ansible scripts from S3 bucket
    sudo mkdir -p /etc/ansible
    sudo aws s3 cp s3://pmo-remote-state/ansible-script/prod-bashscript.sh /etc/ansible/prod-bashscript.sh
    sudo aws s3 cp s3://pmo-remote-state/ansible-script/stage-bashscript.sh /etc/ansible/stage-bashscript.sh
    sudo aws s3 cp s3://pmo-remote-state/ansible-script/deployment.yml /etc/ansible/deployment.yml

    # Create Ansible variable file with Nexus IP and port
    echo "NEXUS_IP: ${var.nexus_ip}:8085" | sudo tee /etc/ansible/ansible_vars_file.yml
    sudo chown -R ec2-user:ec2-user /etc/ansible
    sudo chmod 755 /etc/ansible/prod-bashscript.sh
    sudo chmod 755 /etc/ansible/stage-bashscript.sh

    # Setup cron jobs to run scripts every minute as ec2-user
    echo "* * * * * ec2-user /bin/sh /etc/ansible/prod-bashscript.sh" | sudo tee /etc/cron.d/prod-bashscript
    echo "* * * * * ec2-user /bin/sh /etc/ansible/stage-bashscript.sh" | sudo tee -a /etc/cron.d/prod-bashscript
    sudo chmod 644 /etc/cron.d/prod-bashscript
    sudo systemctl restart crond

    # Install New Relic CLI and agent with environment variables
    curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | sudo bash
    sudo NEW_RELIC_API_KEY="${var.nr_key}" NEW_RELIC_ACCOUNT_ID="${var.nr_acct_id}" NEW_RELIC_REGION=EU /usr/local/bin/newrelic install -y

    # Set hostname
    sudo hostnamectl set-hostname ansible-server
  EOF
}
