#!/bin/bash
set -e

# Convenience script to cleanup and build Packer template

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}==> Starting Packer build process${NC}"
echo

# Step 1: Cleanup existing VMs
echo -e "${YELLOW}Step 1: Cleaning up existing VM${NC}"
"${SCRIPT_DIR}/cleanup-vm.sh"
echo

# Step 2: Run Packer build
echo -e "${YELLOW}Step 2: Running Packer build${NC}"
cd "$PROJECT_DIR"
packer build -var-file=variables.pkrvars.hcl .

echo
echo -e "${GREEN}==> Build process completed successfully!${NC}"
