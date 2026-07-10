#!/bin/bash
set -euo pipefail

# Post-build promotion: replace the live template (VM_ID) with the freshly
# built one (BUILD_VM_ID). Runs only after `packer build` succeeded, so the
# old template survives any build failure.
#
# Proxmox cannot renumber a VM, so the swap clones the new template onto the
# live ID instead: delete old VM_ID -> full-clone BUILD_VM_ID to VM_ID ->
# convert to template -> delete BUILD_VM_ID. Terraform references the
# template by ID, which is why VM_ID must stay stable across rebuilds.
# If this script dies mid-swap the new template still exists at BUILD_VM_ID
# and can be promoted by re-running it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/proxmox-lib.sh"

echo -e "${YELLOW}==> Promoting build ${BUILD_VM_ID} to live template ${VM_ID}${NC}"

new_config=$(vm_config "$BUILD_VM_ID")
if [ -z "$new_config" ] || [ "$(jq -r '.template // 0' <<<"$new_config")" != "1" ]; then
    echo -e "${RED}Error: no template found at ${BUILD_VM_ID}; nothing to promote.${NC}" >&2
    exit 1
fi
if [ "$(jq -r '.name // ""' <<<"$new_config")" != "$TEMPLATE_NAME" ]; then
    echo -e "${RED}Error: VM ${BUILD_VM_ID} is not named '${TEMPLATE_NAME}'. Refusing to promote.${NC}" >&2
    exit 1
fi

old_config=$(vm_config "$VM_ID")
if [ -n "$old_config" ]; then
    # Guard against clobbering a real VM that somehow occupies the live ID.
    if [ "$(jq -r '.template // 0' <<<"$old_config")" != "1" ]; then
        echo -e "${RED}Error: VM ${VM_ID} exists but is not a template. Refusing to delete it.${NC}" >&2
        exit 1
    fi
    echo -e "${YELLOW}Deleting old template ${VM_ID}...${NC}"
    delete_vm "$VM_ID"
fi

echo -e "${YELLOW}Cloning ${BUILD_VM_ID} -> ${VM_ID}...${NC}"
clone_upid=$(proxmox_api POST "/nodes/${PROXMOX_NODE}/qemu/${BUILD_VM_ID}/clone" \
    "newid=${VM_ID}" "name=${TEMPLATE_NAME}" "full=1" | jq -r '.data')
wait_for_task "$clone_upid"

echo -e "${YELLOW}Converting ${VM_ID} to a template...${NC}"
template_upid=$(proxmox_api POST "/nodes/${PROXMOX_NODE}/qemu/${VM_ID}/template" | jq -r '.data')
wait_for_task "$template_upid"

echo -e "${YELLOW}Removing build template ${BUILD_VM_ID}...${NC}"
delete_vm "$BUILD_VM_ID"

echo -e "${GREEN}==> Template '${TEMPLATE_NAME}' is live at VM ID ${VM_ID}.${NC}"
