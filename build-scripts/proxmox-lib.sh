#!/bin/bash
# Shared helpers for the build scripts: reads variables.pkrvars.hcl and wraps
# the Proxmox API. Source this file; it exits the caller if requirements are
# missing.
#
# The build is crash-safe by construction: Packer builds under BUILD_VM_ID
# (a temporary ID) while the live template keeps serving Terraform clones
# under VM_ID. Only after a successful build does promote-template.sh swap
# the new template into VM_ID.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${LIB_DIR}/../variables.pkrvars.hcl"

for cmd in curl jq python3; do
    if ! command -v "$cmd" >/dev/null; then
        echo -e "${RED}Error: required command '$cmd' not found${NC}" >&2
        exit 1
    fi
done

if [ ! -f "$VARS_FILE" ]; then
    echo -e "${RED}Error: variables.pkrvars.hcl not found!${NC}" >&2
    exit 1
fi

# Pre-declare so a value missing from the pkrvars file surfaces as our error
# message below rather than a `set -u` unbound-variable abort in the caller.
PROXMOX_URL="" PROXMOX_USERNAME="" PROXMOX_TOKEN="" PROXMOX_NODE=""
INSECURE_TLS="" VM_ID="" VM_NAME="" TEMPLATE_NAME=""

# Parse the pkrvars file with a real tokenizer instead of grep/sed so that
# comments, indentation, and spacing changes cannot corrupt the values.
# Emits shell-quoted assignments (e.g. PROXMOX_URL='...') which we eval.
eval "$(python3 - "$VARS_FILE" <<'PYEOF'
import re, shlex, sys

wanted = {
    "proxmox_url": "PROXMOX_URL",
    "proxmox_username": "PROXMOX_USERNAME",
    "proxmox_token": "PROXMOX_TOKEN",
    "proxmox_node": "PROXMOX_NODE",
    "insecure_skip_tls_verify": "INSECURE_TLS",
    "vm_id": "VM_ID",
    "vm_name": "VM_NAME",
    "template_name": "TEMPLATE_NAME",
}

# Matches: key = "quoted value"  |  key = bare_value   (trailing # comment ok)
assignment = re.compile(
    r'^\s*(\w+)\s*=\s*(?:"([^"]*)"|([^#\s]+))\s*(?:#.*)?$'
)

for line in open(sys.argv[1]):
    m = assignment.match(line)
    if not m:
        continue
    key, quoted, bare = m.groups()
    if key in wanted:
        print(f"{wanted[key]}={shlex.quote(quoted if quoted is not None else bare)}")
PYEOF
)"

for var in PROXMOX_URL PROXMOX_USERNAME PROXMOX_TOKEN PROXMOX_NODE VM_ID VM_NAME TEMPLATE_NAME; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: could not read '${var,,}' from ${VARS_FILE}${NC}" >&2
        exit 1
    fi
done

# The temporary ID Packer builds under. Derived from VM_ID so the pair stays
# adjacent and unlikely to collide with real VMs (which live far below 9000).
BUILD_VM_ID=$((VM_ID + 1))

if [ "$INSECURE_TLS" = "true" ]; then
    CURL_OPTS="-k"
else
    CURL_OPTS=""
fi

# proxmox_api METHOD ENDPOINT [key=value ...]
# Extra arguments are sent as form fields. Prints the JSON response body.
proxmox_api() {
    local method=$1 endpoint=$2
    shift 2

    local base_url="${PROXMOX_URL%/api2/json}"
    local args=()
    local field
    for field in "$@"; do
        args+=(--data-urlencode "$field")
    done

    curl -sSf -X "$method" $CURL_OPTS \
        -H "Authorization: PVEAPIToken=${PROXMOX_USERNAME}=${PROXMOX_TOKEN}" \
        "${args[@]}" \
        "${base_url}/api2/json${endpoint}"
}

# Prints the VM's config as JSON, or nothing if the VM does not exist.
# Existence is checked via the node's VM list because the config endpoint
# answers HTTP 500 for unknown VMs, which curl -f cannot tell apart from a
# genuine API failure.
vm_config() {
    local vms
    vms=$(proxmox_api GET "/nodes/${PROXMOX_NODE}/qemu")
    if jq -e --argjson id "$1" '.data[] | select(.vmid == $id)' <<<"$vms" >/dev/null; then
        proxmox_api GET "/nodes/${PROXMOX_NODE}/qemu/$1/config" | jq -c '.data'
    fi
}

# Blocks until the Proxmox task (UPID) finishes; fails if the task did.
wait_for_task() {
    local upid=$1
    local status exitstatus
    for _ in $(seq 1 150); do
        status=$(proxmox_api GET "/nodes/${PROXMOX_NODE}/tasks/${upid}/status" | jq -r '.data.status')
        if [ "$status" = "stopped" ]; then
            exitstatus=$(proxmox_api GET "/nodes/${PROXMOX_NODE}/tasks/${upid}/status" | jq -r '.data.exitstatus')
            if [ "$exitstatus" = "OK" ]; then
                return 0
            fi
            echo -e "${RED}Task ${upid} failed: ${exitstatus}${NC}" >&2
            return 1
        fi
        sleep 2
    done
    echo -e "${RED}Timed out waiting for task ${upid}${NC}" >&2
    return 1
}

# Stops (if needed) and deletes a VM, waiting for the delete task to finish.
delete_vm() {
    local vmid=$1

    local status
    status=$(proxmox_api GET "/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/current" | jq -r '.data.status')
    if [ "$status" = "running" ]; then
        echo -e "${YELLOW}VM ${vmid} is running, stopping it first...${NC}"
        local stop_upid
        stop_upid=$(proxmox_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/stop" | jq -r '.data')
        wait_for_task "$stop_upid"
    fi

    local upid
    upid=$(proxmox_api DELETE "/nodes/${PROXMOX_NODE}/qemu/${vmid}?purge=1" | jq -r '.data')
    wait_for_task "$upid"
    echo -e "${GREEN}✓ Deleted VM ${vmid}${NC}"
}
