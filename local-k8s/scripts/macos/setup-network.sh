#!/bin/bash
#
# Sets up macOS host connectivity to Kubernetes VMs on their static IPs.
#
# Multipass QEMU creates two bridges for dual-NIC VMs:
#   - bridge100: eth0 (DHCP) — vmenet0,2,4,6
#   - bridge101: k8snet (static IPs) — vmenet1,3,5,7, bridged with en0
#
# This script adds a gateway alias (192.168.50.1/24) to bridge101 so the
# macOS host can reach VMs on their static IPs directly — no routing
# through DHCP IPs needed.
#
# Run this script with sudo AFTER 'terraform apply' (first run creates VMs).
# Then re-run 'terraform apply' to finish helm chart installations.
# Re-run after VM restarts or macOS reboots to restore the alias.
#
# Static IP allocations:
#   haproxy:  192.168.50.10
#   master-0: 192.168.50.11
#   worker-0: 192.168.50.21
#   worker-1: 192.168.50.22

set -e

GATEWAY_IP="${1:-192.168.50.1}"
STATIC_SUBNET="${GATEWAY_IP%.*}.0"
NETMASK="255.255.255.0"

echo "Setting up macOS connectivity to Kubernetes cluster static IPs..."

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run with sudo"
    exit 1
fi

# Find the k8snet bridge: the one that has BOTH en0 AND vmenet members.
# bridge100 (DHCP) has only vmenet members; bridge101 (k8snet) has en0 + vmenet.
# Detection: look for a bridge that has "member: en0" (MACNAT bridged with en0).
K8S_BRIDGE=$(ifconfig -a | grep -B15 'member: en0' | grep '^bridge' | tail -1 | cut -d: -f1)

if [ -z "$K8S_BRIDGE" ]; then
    echo "Error: Could not find the k8snet bridge (expected bridge101)"
    echo "Make sure 'terraform apply' has been run and VMs are running."
    echo ""
    echo "Debug: bridges found:"
    ifconfig -a | grep '^bridge'
    exit 1
fi

echo "  Found k8snet bridge: $K8S_BRIDGE"

# Remove any stale route that might conflict
route delete -net "$STATIC_SUBNET" 2>/dev/null || true

# Add gateway alias to the k8snet bridge
# Check if alias already exists
if ifconfig "$K8S_BRIDGE" | grep -q "inet $GATEWAY_IP "; then
    echo "  Gateway alias $GATEWAY_IP already exists on $K8S_BRIDGE"
else
    echo "  Adding gateway alias: $GATEWAY_IP/24 on $K8S_BRIDGE..."
    ifconfig "$K8S_BRIDGE" alias "$GATEWAY_IP" netmask "$NETMASK"
fi

# Verify connectivity
echo ""
echo "  Verifying connectivity to haproxy (192.168.50.10)..."
if ping -c 1 -t 3 192.168.50.10 > /dev/null 2>&1; then
    echo "  Connectivity OK!"
else
    echo "  Warning: ping to 192.168.50.10 failed. It may take a moment to converge."
    echo "  Try: ping 192.168.50.10"
fi

echo ""
echo "Network setup complete!"
echo ""
echo "Configuration:"
echo "  Bridge: $K8S_BRIDGE with alias $GATEWAY_IP/24"
echo "  Host can reach 192.168.50.0/24 directly via $K8S_BRIDGE"
echo ""
echo "Next steps:"
echo "  1. Re-run: cd $(pwd) && terraform apply -auto-approve"
echo "  2. Verify: kubectl --kubeconfig ~/.kube/config-multipass get nodes"
