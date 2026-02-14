#!/bin/bash
# Reset script for macOS
# Deletes all Multipass VMs and cleans up generated files

echo "Deleting all Multipass VMs..."
multipass delete --all
multipass purge

echo "Cleaning up generated files..."

# Remove cloud-init files (check both directories)
rm -f macos/cloud-init-*.yaml 2>/dev/null
rm -f multipass/cloud-init-*.yaml 2>/dev/null

# Remove HAProxy config files
rm -f macos/haproxy_*.cfg 2>/dev/null
rm -f multipass/haproxy_*.cfg 2>/dev/null

# Remove Terraform state
rm -f macos/terraform.tfstate* 2>/dev/null
rm -f terraform.tfstate* 2>/dev/null

# Remove temporary files
rm -f /tmp/hosts_ip.txt 2>/dev/null

# Remove kubeconfig
rm -f ~/.kube/config-multipass 2>/dev/null

# Remove multipass log
rm -f macos/multipass.log 2>/dev/null

echo "Cleanup complete!"
