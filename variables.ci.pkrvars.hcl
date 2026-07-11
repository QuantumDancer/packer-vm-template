# Non-secret build values for CI. The pipeline copies this file to
# variables.pkrvars.hcl and appends proxmox_token / ssh_password from
# GitLab CI variables — see .gitlab-ci.yml.

# Proxmox Connection
proxmox_url              = "https://proxmox-01.home.rottlr.de:8006/api2/json"
proxmox_username         = "root@pam!packer"
insecure_skip_tls_verify = false
proxmox_node             = "proxmox-01"

# ISO Configuration
iso_file = "local:iso/rhel-9.8-x86_64-dvd.iso"

# VM Configuration
vm_id         = 9001
vm_name       = "rhel9-packer-build"
template_name = "rhel-9-template"

# Hardware Configuration
cpu_cores   = 4
cpu_sockets = 1
memory      = 4096
disk_size   = "10G"

# Storage and Network
storage_pool   = "local-zfs"
network_bridge = "vmbr1"

# SSH Configuration
# The password comes from CI and must match the packer user's hash in
# kickstart/ks.cfg.
ssh_username = "packer"
