#!/bin/bash
set -euo pipefail

# Pre-build cleanup: remove a leftover temporary build VM (BUILD_VM_ID) from
# a previous failed run. The live template (VM_ID) is never touched here —
# it stays available for Terraform clones until promote-template.sh replaces
# it after a successful build.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/proxmox-lib.sh"

echo -e "${YELLOW}==> Checking for leftover build VM ${BUILD_VM_ID} on node ${PROXMOX_NODE}${NC}"

config=$(vm_config "$BUILD_VM_ID")

if [ -z "$config" ]; then
    echo -e "${GREEN}Build VM ${BUILD_VM_ID} does not exist. Ready to build.${NC}"
    exit 0
fi

# Only delete what this workflow could have created: the in-progress build VM
# or an already-templated build that was never promoted. Anything else at this
# ID is someone else's VM — refuse rather than destroy it.
name=$(jq -r '.name // ""' <<<"$config")
if [ "$name" != "$VM_NAME" ] && [ "$name" != "$TEMPLATE_NAME" ]; then
    echo -e "${RED}Error: VM ${BUILD_VM_ID} exists but is named '${name}', not" \
        "'${VM_NAME}' or '${TEMPLATE_NAME}'. Refusing to delete it.${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}Removing leftover build VM ${BUILD_VM_ID} ('${name}')...${NC}"
delete_vm "$BUILD_VM_ID"

echo -e "${GREEN}==> Cleanup complete! Ready to run Packer build.${NC}"
