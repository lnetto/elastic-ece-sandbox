# Elastic Cloud Enterprise (ECE) Lab Setup Scripts

Automated scripts for setting up a multi-node Elastic Cloud Enterprise lab environment using Multipass VMs.

## Overview

These scripts create a complete ECE cluster across multiple availability zones for testing and development purposes. The setup includes:

- Multiple Ubuntu VMs managed by Multipass
- Automated Docker installation and configuration
- Multi-zone ECE cluster deployment

## Prerequisites

- **Multipass** installed and running
- **Optional**: `jq` for JSON parsing (script falls back to grep if unavailable)

## Scripts

### 1. `setup-ece-lab.sh`

Main orchestration script that creates and configures the entire ECE cluster.

**Configuration variables** (edit at top of script):

```bash
NUM_AVAILABILITY_ZONES=2      # Number of availability zones
NODES_PER_ZONE=2              # Nodes per zone (total = zones × nodes)
VM_CPUS=4                     # CPU cores per VM
VM_MEMORY="16G"               # RAM per VM
VM_DISK="30G"                 # Disk space per VM
AVAILABILITY_ZONE_PREFIX="AZ" # Naming prefix for zones
```

### 2. `prepare-ece-vm.sh`

VM preparation script that runs on each node to configure the environment.

### 3. `reset-multipass.sh`

Cleanup script to delete all Multipass VMs and start fresh.

## Quick Start

### Basic Setup (2 zones, 2 nodes each = 4 VMs)

```bash
# 1. Make scripts executable
chmod +x setup-ece-lab.sh prepare-ece-vm.sh reset-multipass.sh

# 2. Run the setup
./setup-ece-lab.sh
```

The script will:

- Create 4 VMs (ece-az1-1, ece-az1-2, ece-az2-1, ece-az2-2)
- Install and configure Docker on each
- Install ECE with the primary node on ece-az1-1
- Join additional nodes to the cluster

**Installation time**: ~30-45 minutes depending on your system

### Custom Configuration

Edit `setup-ece-lab.sh` before running to adjust:

```bash
# For a smaller lab (1 zone, 2 nodes)
NUM_AVAILABILITY_ZONES=1
NODES_PER_ZONE=2
VM_MEMORY="12G"  # Reduce if needed

# For a larger lab (3 zones, 3 nodes)
NUM_AVAILABILITY_ZONES=3
NODES_PER_ZONE=3
```

## Usage

### Accessing ECE

After installation completes, you'll see output like:

```
Primary node: ece-az1-1 (192.168.64.2)
Root password: <password>
Admin console root password: <password>
```

**Access the ECE Admin Console**:

```
https://<primary-node-ip>:12443
Username: admin
Password: <adminconsole_root_password>
```

**Access Elasticsearch/Kibana** through deployments created in the Admin Console.

## Support

These scripts are provided as-is for lab and development purposes. For production ECE deployments, consult the official Elastic documentation and consider Elastic's professional services.
