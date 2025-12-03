#!/bin/bash

set -e  # Exit on error
set -u  # Exit on undefined variable

# Configuration
NUM_AVAILABILITY_ZONES=2
NODES_PER_ZONE=2

VM_CPUS=4
VM_MEMORY="16G"
VM_DISK="30G"

AVAILABILITY_ZONE_PREFIX="MY_ZONE"

MEMORY_SETTINGS='{"runner":{"xms":"1G","xmx":"1G"},"allocator":{"xms":"4G","xmx":"4G"},"zookeeper":{"xms":"4G","xmx":"4G"},"director":{"xms":"1G","xmx":"1G"},"constructor":{"xms":"4G","xmx":"4G"},"admin-console":{"xms":"4G","xmx":"4G"}}'

# Calculate total number of nodes
TOTAL_NODES=$((NUM_AVAILABILITY_ZONES * NODES_PER_ZONE))

# Function to generate VM name
get_vm_name() {
    local az=$1
    local node=$2
    echo "ece-az${az}-${node}"
}

echo "=== Configuration ==="
echo "Availability Zones: $NUM_AVAILABILITY_ZONES"
echo "Nodes per Zone: $NODES_PER_ZONE"
echo "Total Nodes: $TOTAL_NODES"
echo "VM specs: ${VM_CPUS} CPUs, ${VM_MEMORY} RAM, ${VM_DISK} disk"
echo ""

echo "=== Cleaning up existing ECE VMs ==="
# Clean up any existing ece* VMs
for vm in $(multipass list | grep '^ece' | awk '{print $1}'); do
    echo "Stopping and deleting $vm..."
    multipass stop "$vm"
    multipass delete "$vm"
done
multipass purge

echo "=== Creating $TOTAL_NODES ECE nodes across $NUM_AVAILABILITY_ZONES availability zones ==="

# Create VMs with naming: ece-az<zone>-<node>
for az in $(seq 1 $NUM_AVAILABILITY_ZONES); do
    for node in $(seq 1 $NODES_PER_ZONE); do
        vm_name=$(get_vm_name $az $node)
        
        echo "Creating ${vm_name} (Zone ${az}, Node ${node})..."
        multipass launch --name "${vm_name}" --cpus "$VM_CPUS" --memory "$VM_MEMORY" --disk "$VM_DISK"
        
        echo "Preparing ${vm_name}..."
        multipass transfer prepare-ece-vm.sh "${vm_name}:/tmp/"
        multipass exec "${vm_name}" -- bash /tmp/prepare-ece-vm.sh
        
        echo "Restarting ${vm_name}..."
        multipass stop "${vm_name}"
        multipass start "${vm_name}"
    done
done

echo "=== Current VM list ==="
multipass list

# Get the primary node name (first node in first zone)
PRIMARY_NODE=$(get_vm_name 1 1)

echo "=== Installing ECE on primary node (${PRIMARY_NODE}) ==="
# Install ECE on the first host
multipass exec "${PRIMARY_NODE}" -- curl -fsSL https://download.elastic.co/cloud/elastic-cloud-enterprise.sh -o /tmp/install-ece.sh

multipass exec "${PRIMARY_NODE}" -- sudo -u elastic bash /tmp/install-ece.sh install \
    --availability-zone "${AVAILABILITY_ZONE_PREFIX}-1" \
    --memory-settings "$MEMORY_SETTINGS" 2>&1 | tee -a "install-${PRIMARY_NODE}.log"

# Get the primary host IP
HOST_IP=$(multipass info "${PRIMARY_NODE}" | grep IPv4 | awk '{print $2}')
echo "Primary node IP: $HOST_IP"

echo "=== Retrieving secrets from ${PRIMARY_NODE} ==="
# Retrieve bootstrap secrets from primary node
multipass transfer "${PRIMARY_NODE}:/mnt/data/elastic/bootstrap-state/bootstrap-secrets.json" ./ece-bootstrap-secrets.json

# Extract roles token from the secrets file
if command -v jq &> /dev/null; then
    ROLES_TOKEN=$(jq -r '.emergency_all_roles_except_allocator_token' ./ece-bootstrap-secrets.json)
    echo "Roles token extracted using jq"
else
    # Fallback to grep if jq is not available
    ROLES_TOKEN=$(grep -oP '"emergency_all_roles_except_allocator_token"\s*:\s*"\K[^"]+' ./ece-bootstrap-secrets.json)
    echo "Roles token extracted using grep"
fi

if [ -z "$ROLES_TOKEN" ]; then
    echo "ERROR: Failed to extract roles token from bootstrap secrets"
    exit 1
fi

echo "Roles token: ${ROLES_TOKEN:0:50}..." # Show first 50 chars only

echo "=== Installing ECE on secondary nodes ==="
# Install ECE on additional hosts
for az in $(seq 1 $NUM_AVAILABILITY_ZONES); do
    # Skip first node in first zone (already installed as primary)
    start_node=1
    if [ $az -eq 1 ]; then
        start_node=2
    fi
    
    for node in $(seq $start_node $NODES_PER_ZONE); do
        vm_name=$(get_vm_name $az $node)
        echo "Installing ECE on ${vm_name} (Zone ${az}, Node ${node})..."
        
        multipass exec "${vm_name}" -- curl -fsSL https://download.elastic.co/cloud/elastic-cloud-enterprise.sh -o /tmp/install-ece.sh
        
        multipass exec "${vm_name}" -- sudo -u elastic bash /tmp/install-ece.sh install \
            --coordinator-host "$HOST_IP" \
            --roles-token "$ROLES_TOKEN" \
            --roles "director,coordinator,proxy,allocator" \
            --availability-zone "${AVAILABILITY_ZONE_PREFIX}-${az}" \
            --memory-settings "$MEMORY_SETTINGS" 2>&1 | tee -a "install-${vm_name}.log"
    done
done

echo "=== ECE Installation Complete ==="
echo "Primary node: ${PRIMARY_NODE} ($HOST_IP)"
echo ""
echo "Node distribution:"
for az in $(seq 1 $NUM_AVAILABILITY_ZONES); do
    echo "  Availability Zone ${AVAILABILITY_ZONE_PREFIX}-${az}:"
    for node in $(seq 1 $NODES_PER_ZONE); do
        vm_name=$(get_vm_name $az $node)
        NODE_IP=$(multipass info "${vm_name}" | grep IPv4 | awk '{print $2}')
        echo "    - ${vm_name} ($NODE_IP)"
    done
done
echo ""
echo "Bootstrap secrets saved: ece-bootstrap-secrets.json"
echo ""
echo "Key credentials:"
if command -v jq &> /dev/null; then
    echo "Root password: $(jq -r '.root_password' ./ece-bootstrap-secrets.json)"
    echo "Admin console root password: $(jq -r '.adminconsole_root_password' ./ece-bootstrap-secrets.json)"
fi