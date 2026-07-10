#!/bin/bash
set -e

echo "==> Starting template cleanup process"

# Remove machine-specific configurations
echo "==> Removing machine-id"
sudo rm -f /etc/machine-id
sudo touch /etc/machine-id

# Remove SSH host keys
echo "==> Removing SSH host keys"
sudo rm -f /etc/ssh/ssh_host_*

# Clean up network configs
echo "==> Cleaning up network configurations"
sudo rm -f /etc/NetworkManager/system-connections/*

# Clean up subscription manager
echo "==> Cleaning up Red Hat subscription manager"
sudo subscription-manager remove --all || true
sudo subscription-manager unregister || true
sudo subscription-manager clean || true

# Remove RHSM specific files
echo "==> Removing RHSM files"
sudo rm -rf /etc/rhsm/facts/*
sudo rm -rf /etc/pki/consumer/*
sudo rm -rf /etc/pki/entitlement/*

# Remove insights specific files
echo "==> Removing insights files"
sudo rm -f /etc/insights-client/.registered
sudo rm -f /etc/insights-client/.unregistered
sudo rm -f /etc/insights-client/machine-id

# Clean up logs
echo "==> Cleaning up log files"
sudo find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
sudo rm -rf /var/log/journal/*
sudo truncate -s 0 /var/log/audit/audit.log

# Clean up temporary files
echo "==> Cleaning up temporary files"
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

# Clean up shell history
echo "==> Cleaning up shell history"
history -c
sudo rm -f /root/.bash_history
rm -f ~/.bash_history

# Clean up cloud-init state so it runs on first boot
echo "==> Cleaning cloud-init state"
sudo cloud-init clean --logs --seed

# The packer build user cannot delete itself during provisioning (these
# scripts run over its own SSH session), so have cloud-init remove it on the
# first boot of each cloned VM. Installed after `cloud-init clean`, which
# wipes /var/lib/cloud including the scripts directory.
echo "==> Installing first-boot script to remove the packer build user"
sudo mkdir -p /var/lib/cloud/scripts/per-instance
sudo tee /var/lib/cloud/scripts/per-instance/10-remove-build-user.sh >/dev/null <<'EOF'
#!/bin/sh
userdel -rf packer 2>/dev/null || true
EOF
sudo chmod 0755 /var/lib/cloud/scripts/per-instance/10-remove-build-user.sh

# Clean up package cache
echo "==> Cleaning package cache"
sudo dnf clean all

# Sync filesystem
echo "==> Syncing filesystem"
sync

echo "==> Template cleanup complete! VM is ready to be converted to a template."
