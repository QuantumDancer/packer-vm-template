#!/bin/bash
set -e

echo "==> Configuring cloud-init for Proxmox template"

# cloud-init and qemu-guest-agent are already installed via kickstart
# Ensure they are enabled
sudo systemctl enable qemu-guest-agent
sudo systemctl enable cloud-init-local.service
sudo systemctl enable cloud-init.service
sudo systemctl enable cloud-config.service
sudo systemctl enable cloud-final.service

# Ensure sr_mod (CD-ROM driver) is loaded at boot for cloud-init drive
echo "==> Ensuring CD-ROM driver is available"
sudo tee /etc/modules-load.d/cloud-init.conf >/dev/null <<'EOF'
sr_mod
EOF

# Configure cloud-init for Proxmox
echo "==> Configuring cloud-init datasource for Proxmox"
sudo tee /etc/cloud/cloud.cfg.d/99_pve.cfg >/dev/null <<'EOF'
datasource_list: [ NoCloud, ConfigDrive, None ]
EOF

# Disable package upgrade module entirely (systems may not be registered with Red Hat)
# Workaround of https://github.com/bpg/terraform-provider-proxmox/issues/1079
# as we cannot disable upgrading via the terraform proxmox provider
echo "==> Disabling package upgrade module"
sudo tee /etc/cloud/cloud.cfg.d/98_disable_updates.cfg >/dev/null <<'EOF'
# Disable package upgrade module entirely
# Systems may not be registered with Red Hat subscription
# Remove package_update_upgrade_install from cloud_final_modules
cloud_final_modules:
  - write_files_deferred
  - puppet
  - chef
  - ansible
  - mcollective
  - salt_minion
  - reset_rmc
  - scripts_vendor
  - scripts_per_once
  - scripts_per_boot
  - scripts_per_instance
  - scripts_user
  - ssh_authkey_fingerprints
  - keys_to_console
  - install_hotplug
  - phone_home
  - final_message
  - power_state_change
EOF

echo "==> Cloud-init configuration complete"
