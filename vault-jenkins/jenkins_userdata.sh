#!/bin/bash

set -e  # Exit on any error
set -x  # Print commands for debugging

# Set region variable (ensure it's defined before use)
region="$${region:-eu-west-1}"

# Update packages
sudo yum update -y

# Install dependencies: wget, git, pip, maven
sudo yum install -y wget git python3-pip maven

# Install Amazon SSM Agent (dnf is for Amazon Linux 2+ or RHEL 8+)
if ! systemctl status amazon-ssm-agent >/dev/null 2>&1; then
 sudo dnf install -y https://s3.$${region}.amazonaws.com/amazon-ssm-$${region}/latest/linux_amd64/amazon-ssm-agent.rpm
fi

# Install Session Manager plugin
curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o session-manager-plugin.rpm
sudo yum install -y session-manager-plugin.rpm

# Add Jenkins repo and import key
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

# Upgrade system and install Java + Jenkins
sudo yum upgrade -y
sudo yum install -y java-17-openjdk jenkins

# Configure Jenkins to run as root (not ideal for production)
sudo sed -i 's/^User=jenkins/User=root/' /usr/lib/systemd/system/jenkins.service
sudo systemctl daemon-reload
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Add ec2-user to Jenkins group (and vice versa)
sudo usermod -aG jenkins ec2-user

# Install Trivy for container scanning
RELEASE_VERSION=$(grep -Po '(?<=VERSION_ID=")[0-9]+' /etc/os-release)
cat <<EOT | sudo tee /etc/yum.repos.d/trivy.repo
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$${RELEASE_VERSION}/\$basearch/
gpgcheck=0
enabled=1
EOT

sudo yum -y update
sudo yum -y install trivy

# Install Docker
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io

# Start and enable Docker
sudo systemctl enable docker
sudo systemctl start docker

# Add users to docker group
sudo usermod -aG docker ec2-user
sudo usermod -aG docker jenkins

# Set permissions on docker.sock (be cautious)
sudo chmod 666 /var/run/docker.sock

# Install AWS CLI v2
sudo yum install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -o awscliv2.zip
sudo ./aws/install
sudo ln -sf /usr/local/bin/aws /usr/bin/aws

# Install New Relic agent
export NEW_RELIC_API_KEY=""
export NEW_RELIC_ACCOUNT_ID=""
export NEW_RELIC_REGION=""
curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash
sudo /usr/local/bin/newrelic install

# Set hostname to jenkins
sudo hostnamectl set-hostname jenkins
