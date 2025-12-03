#!/bin/bash
set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Update system packages
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh --version 27.0

# Add ubuntu user to docker group
sudo usermod -aG docker ubuntu

# Configure GRUB for cgroup settings
# Check if cgroup settings already exist
if grep -q "cgroup_enable=memory" /etc/default/grub; then
    echo "GRUB cgroup settings already configured, skipping..."
else
    # Only modify if GRUB_CMDLINE_LINUX is empty or add settings properly
    if grep -q '^GRUB_CMDLINE_LINUX=""' /etc/default/grub; then
        sudo sed -i 's/^GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1 cgroup.memory=nokmem"/' /etc/default/grub
    else
        sudo sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"$/GRUB_CMDLINE_LINUX="\1 cgroup_enable=memory swapaccount=1 cgroup.memory=nokmem"/' /etc/default/grub
    fi

    # Remove any double spaces that might have been created
    sudo sed -i 's/GRUB_CMDLINE_LINUX="  */GRUB_CMDLINE_LINUX="/' /etc/default/grub

    sudo update-grub
    echo "GRUB configuration updated successfully!"
fi

# Configure sysctl settings
echo "Configuring sysctl settings..."
cat <<'EOF' | sudo tee -a /etc/sysctl.conf
# Required by Elasticsearch
vm.max_map_count=262144
# Enable forwarding for Docker networking
net.ipv4.ip_forward=1
# Decrease TCP retransmissions for Elasticsearch
net.ipv4.tcp_retries2=5
# Prevent early swapping
vm.swappiness=1
# System-wide file limits
fs.file-max=2097152
fs.nr_open=2097152
EOF

sudo sysctl -p

# Configure network settings for Cloud Enterprise
echo "Configuring network settings for Cloud Enterprise..."
cat <<'SETTINGS' | sudo tee /etc/sysctl.d/70-cloudenterprise.conf
net.ipv4.tcp_max_syn_backlog=65536
net.core.somaxconn=32768
net.core.netdev_max_backlog=32768
SETTINGS

sudo sysctl --system

# Configure Docker systemd service
echo "Configuring Docker systemd service..."
sudo mkdir -p /etc/systemd/system/docker.service.d

cat <<'EOF' | sudo tee /etc/systemd/system/docker.service.d/docker.conf
[Unit]
Description=Docker Service
After=multi-user.target

[Service]
Environment="DOCKER_OPTS=-H unix:///run/docker.sock --data-root /mnt/data/docker --storage-driver=overlay2 --bip=172.17.42.1/16 --raw-logs --log-opt max-size=500m --log-opt max-file=10 --icc=false --default-ulimit nofile=1024000:1024000"
ExecStart=
ExecStart=/usr/bin/dockerd $DOCKER_OPTS
EOF

# Apply Docker daemon configuration
echo "Applying Docker daemon configuration..."
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl enable docker

# Create elastic user
echo "Creating elastic user..."
sudo useradd -m -s /bin/bash elastic
sudo usermod -aG docker elastic
sudo usermod -aG sudo elastic
echo "elastic ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/elastic > /dev/null

# Create data directory
echo "Creating data directory..."
sudo mkdir -p /mnt/data/docker
sudo chown -R elastic:elastic /mnt/data

# Configure system limits
echo "Configuring system limits..."
sudo tee -a /etc/security/limits.conf > /dev/null <<'EOF'
# ECE system limits
*                soft    nofile         1024000
*                hard    nofile         1024000
*                soft    memlock        unlimited
*                hard    memlock        unlimited
elastic          soft    nofile         1024000
elastic          hard    nofile         1024000
elastic          soft    memlock        unlimited
elastic          hard    memlock        unlimited
elastic          soft    nproc          unlimited
elastic          hard    nproc          unlimited
root             soft    nofile         1024000
root             hard    nofile         1024000
root             soft    memlock        unlimited
EOF

