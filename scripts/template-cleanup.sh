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

# Clean up package cache
echo "==> Cleaning package cache"
sudo dnf clean all

# Sync filesystem
echo "==> Syncing filesystem"
sync

# TODO: This does not work because this script is executed via an ssh session of this user
# # Remove packer user (temporary build user)
# echo "==> Removing packer user"
# sudo userdel -r packer || true

echo "==> Template cleanup complete! VM is ready to be converted to a template."
