#!/bin/bash

# Updating the instance
sudo yum update -y
sudo yum upgrade -y

# Install Docker and its dependencies, start Docker service
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install docker-ce -y

# Configure Docker daemon for insecure registry
sudo bash -c 'cat <<EOT > /etc/docker/daemon.json
{
  "insecure-registries" : ["${nexus_ip}:8085"]
}
EOT'

# Start Docker and enable on boot
sudo systemctl start docker
sudo systemctl enable docker

# Add ec2-user to docker group
sudo usermod -aG docker ec2-user

# Create scripts directory
sudo mkdir -p /home/ec2-user/scripts

# Create container management script
cat << 'EOF' > "/home/ec2-user/scripts/script.sh"
#!/bin/bash
set -x

# Variables substituted by Terraform at templatefile() time
IMAGE_NAME="${nexus_ip}:8085/petclinicapps"
NEXUS_IP="${nexus_ip}:8085"
PRIMARY_PORT=${port}

# Determine alternate port
if [ "$PRIMARY_PORT" -eq 8080 ]; then
  ALTERNATE_PORT=8081
else
  ALTERNATE_PORT=8080
fi

# Docker login
authenticate_docker() {
  docker login --username=admin --password=admin123 $NEXUS_IP
}

# Get active container port
get_active_port() {
  for p in $PRIMARY_PORT $ALTERNATE_PORT; do
    if docker ps | grep -q ":$p->8080"; then
      echo "$p"
      return
    fi
  done
  echo "none"
}

# Pull image and check if it's new
check_for_image_update() {
  docker pull $IMAGE_NAME > /tmp/pulled_image.log 2>&1
  grep -q "Downloaded newer image" /tmp/pulled_image.log
  return $?
}

# Run new container
deploy_container() {
  local new_port=$1
  local cname="app-$${new_port}"
  docker run -d --name $cname -p $${new_port}:8080 $IMAGE_NAME
}

# Stop & remove old container
cleanup_old_container() {
  local old_port=$1
  local cname="app-$${old_port}"
  docker stop $cname && docker rm $cname
}

# Main logic
main() {
  authenticate_docker
  if check_for_image_update; then
    ACTIVE_PORT=$(get_active_port)
    if [ "$ACTIVE_PORT" == "$PRIMARY_PORT" ]; then
      NEW_PORT=$ALTERNATE_PORT
    else
      NEW_PORT=$PRIMARY_PORT
    fi

    deploy_container $NEW_PORT
    sleep 15

    if [ "$ACTIVE_PORT" != "none" ]; then
      cleanup_old_container $ACTIVE_PORT
    fi

    echo "Switched to container on port $NEW_PORT"
  else
    echo "Image is already up-to-date."
  fi
}

main
EOF

# Set permissions
sudo chown ec2-user:ec2-user /home/ec2-user/scripts/script.sh
sudo chmod 755 /home/ec2-user/scripts/script.sh

# Restart Docker
sudo systemctl restart docker

# Install New Relic CLI and monitor
curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash
sudo NEW_RELIC_API_KEY="${nr_key}" \
     NEW_RELIC_ACCOUNT_ID="${nr_acct_id}" \
     NEW_RELIC_REGION="EU" \
     /usr/local/bin/newrelic install -y

# Set hostname and reboot
sudo hostnamectl set-hostname prod-instance
sudo reboot
