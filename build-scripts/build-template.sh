#!/bin/bash
set -euo pipefail

# Builds the RHEL 9 template without ever leaving Proxmox template-less:
# Packer builds under a temporary VM ID while the live template keeps
# serving Terraform clones, and only a successful build gets promoted.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
source "${SCRIPT_DIR}/proxmox-lib.sh"

echo -e "${YELLOW}==> Starting Packer build process${NC}"
echo

echo -e "${YELLOW}Step 1: Cleaning up leftover build VM${NC}"
"${SCRIPT_DIR}/cleanup-vm.sh"
echo

echo -e "${YELLOW}Step 2: Running Packer build (VM ${BUILD_VM_ID}; live template ${VM_ID} stays untouched)${NC}"
cd "$PROJECT_DIR"
packer build -var-file=variables.pkrvars.hcl -var "vm_id=${BUILD_VM_ID}" .
echo

echo -e "${YELLOW}Step 3: Promoting new template to VM ID ${VM_ID}${NC}"
"${SCRIPT_DIR}/promote-template.sh"

echo
echo -e "${GREEN}==> Build process completed successfully!${NC}"
