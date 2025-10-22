#!/bin/bash
set -e

# Proxmox VM Cleanup Script
# This script deletes the build VM before running Packer

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse variables from variables.pkrvars.hcl
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/../variables.pkrvars.hcl"

if [ ! -f "$VARS_FILE" ]; then
    echo -e "${RED}Error: variables.pkrvars.hcl not found!${NC}"
    exit 1
fi

# Extract values from HCL file
PROXMOX_URL=$(grep 'proxmox_url' "$VARS_FILE" | sed 's/.*= *"\(.*\)".*/\1/')
PROXMOX_USERNAME=$(grep 'proxmox_username' "$VARS_FILE" | sed 's/.*= *"\(.*\)".*/\1/')
PROXMOX_TOKEN=$(grep 'proxmox_token' "$VARS_FILE" | sed 's/.*= *"\(.*\)".*/\1/')
PROXMOX_NODE=$(grep 'proxmox_node' "$VARS_FILE" | sed 's/.*= *"\(.*\)".*/\1/')
VM_ID=$(grep '^vm_id' "$VARS_FILE" | sed 's/.*= *\([0-9]*\).*/\1/')

# Verify TLS setting
INSECURE_TLS=$(grep 'insecure_skip_tls_verify' "$VARS_FILE" | sed 's/.*= *\(.*\)/\1/')
if [ "$INSECURE_TLS" = "true" ]; then
    CURL_OPTS="-k"
else
    CURL_OPTS=""
fi

echo -e "${YELLOW}==> Checking for existing VMs on node ${PROXMOX_NODE}${NC}"

# Function to make API calls
proxmox_api() {
    local method=$1
    local endpoint=$2
    local data=$3

    local base_url="${PROXMOX_URL%/api2/json}"
    local auth_header="Authorization: PVEAPIToken=${PROXMOX_USERNAME}=${PROXMOX_TOKEN}"

    if [ -n "$data" ]; then
        curl -s -X "$method" \
            $CURL_OPTS \
            -H "$auth_header" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${base_url}/api2/json${endpoint}"
    else
        curl -s -X "$method" \
            $CURL_OPTS \
            -H "$auth_header" \
            "${base_url}/api2/json${endpoint}"
    fi
}

# Function to delete VM
delete_vm() {
    local vmid=$1
    local vm_name=$2

    echo -e "${YELLOW}Attempting to delete VM ${vmid} (${vm_name})...${NC}"

    # First, try to stop the VM if it's running
    local status=$(proxmox_api GET "/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/current" 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

    if [ "$status" = "running" ]; then
        echo -e "${YELLOW}VM is running, stopping it first...${NC}"
        proxmox_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/stop" >/dev/null
        sleep 3
    fi

    # Delete the VM
    local response=$(proxmox_api DELETE "/nodes/${PROXMOX_NODE}/qemu/${vmid}")

    if echo "$response" | grep -q '"data"'; then
        echo -e "${GREEN}✓ Successfully deleted VM ${vmid}${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to delete VM ${vmid}${NC}"
        return 1
    fi
}

# Check if build VM exists and delete it
echo -e "${YELLOW}Checking for build VM (ID: ${VM_ID})...${NC}"
VM_EXISTS=$(proxmox_api GET "/nodes/${PROXMOX_NODE}/qemu/${VM_ID}/status/current" 2>/dev/null | grep -o '"status"' || echo "")

if [ -n "$VM_EXISTS" ]; then
    echo -e "${YELLOW}Found build VM ${VM_ID}${NC}"
    delete_vm "$VM_ID" "build VM"
else
    echo -e "${GREEN}Build VM ${VM_ID} does not exist${NC}"
fi

echo -e "${GREEN}==> Cleanup complete! Ready to run Packer build.${NC}"
