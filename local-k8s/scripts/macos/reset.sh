#!/bin/bash
# Reset script for macOS
# Deletes all Multipass VMs and cleans up generated files

echo "Deleting all Multipass VMs..."
multipass delete --all
multipass purge

echo "Cleaning up generated files..."

# Remove cloud-init files
rm -f cloud-init-*.yaml 2>/dev/null

# Remove HAProxy config files
rm -f haproxy_*.cfg 2>/dev/null

# Remove Terraform state
rm -f terraform.tfstate* 2>/dev/null
rm -rf .terraform 2>/dev/null
rm -f .terraform.lock.hcl 2>/dev/null

# Remove temporary files
rm -f /tmp/hosts_ip.txt 2>/dev/null

# Remove kubeconfig
rm -f ~/.kube/config-multipass 2>/dev/null

# Remove multipass log
rm -f multipass.log 2>/dev/null

# Remove bridge alias (if setup-network.sh was run)
K8S_BRIDGE=$(ifconfig -a 2>/dev/null | grep -B15 'member: en0' | grep '^bridge' | tail -1 | cut -d: -f1)
if [ -n "$K8S_BRIDGE" ] && ifconfig "$K8S_BRIDGE" 2>/dev/null | grep -q "inet 192.168.50.1 "; then
    echo "Removing 192.168.50.1 alias from $K8S_BRIDGE (requires sudo)..."
    sudo ifconfig "$K8S_BRIDGE" -alias 192.168.50.1 2>/dev/null || echo "  (skipped - run with sudo to remove alias)"
fi

echo "Cleanup complete!"
