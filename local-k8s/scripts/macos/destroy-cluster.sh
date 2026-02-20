#!/bin/bash
#
# Destroys the macOS K8s cluster, cleaning up all resources.
#
# Performs a thorough cleanup:
#   1. Terraform destroy (apps then infra)
#   2. Multipass VM deletion
#   3. State file cleanup
#   4. Network bridge alias removal
#
# All output is logged to logs/destroy-cluster_<timestamp>.log for troubleshooting.
#

set -uo pipefail

# -- Configuration ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/destroy-cluster_$TIMESTAMP.log"

# -- Colors --------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
NC='\033[0m'

# -- Logging helpers -----------------------------------------------------------

log() {
    local level="${2:-INFO}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1" >> "$LOG_FILE"
}

step() {
    echo -e "\n${CYAN}[$1] $2${NC}"
    log "STEP $1 - $2"
}

ok() {
    echo -e "  ${GREEN}[OK]${NC} $1"
    log "$1" "OK"
}

info() {
    echo -e "  ${GRAY}$1${NC}"
    log "$1"
}

run_logged() {
    local description="$1"
    shift
    log "Executing: $*"
    info "$description..."
    "$@" 2>&1 | tee -a "$LOG_FILE" || true
}

# -- Main ----------------------------------------------------------------------

cd "$SCRIPT_DIR"

echo "=== destroy-cluster started at $(date '+%Y-%m-%d %H:%M:%S') ===" > "$LOG_FILE"

echo -e "${WHITE}============================================${NC}"
echo -e "${WHITE} Destroy macOS K8s Cluster${NC}"
echo -e "${WHITE}============================================${NC}"
echo -e "  ${GRAY}Log file: $LOG_FILE${NC}"
echo ""
echo -e "${YELLOW}This will destroy ALL VMs and clean up state files.${NC}"

read -p "Are you sure? (y/N) " confirm
if [ "$confirm" != "y" ]; then
    echo "Cancelled."
    exit 0
fi

# Step 1: Terraform destroy applications
step "1/5" "Destroying Terraform applications..."
if [ -d "apps/.terraform" ]; then
    run_logged "terraform destroy (apps)" terraform -chdir=apps destroy -auto-approve
    ok "Applications Terraform destroy complete."
else
    info "No apps Terraform state found, skipping."
fi

# Step 2: Terraform destroy infrastructure
step "2/5" "Destroying Terraform infrastructure..."
if [ -d "infra/.terraform" ]; then
    run_logged "terraform destroy (infra)" terraform -chdir=infra destroy -auto-approve
    ok "Infrastructure Terraform destroy complete."
else
    info "No infra Terraform state found, skipping."
fi

# Step 3: Delete Multipass VMs
step "3/5" "Deleting Multipass VMs..."
run_logged "multipass delete --all" multipass delete --all
run_logged "multipass purge" multipass purge
ok "Multipass VMs deleted."

# Step 4: Clean up state files
step "4/5" "Cleaning up state files..."

cleanup_paths=(
    "infra/terraform.tfstate"
    "infra/terraform.tfstate.backup"
    "infra/.terraform.tfstate.lock.info"
    "infra/.terraform"
    "infra/.terraform.lock.hcl"
    "apps/terraform.tfstate"
    "apps/terraform.tfstate.backup"
    "apps/.terraform.tfstate.lock.info"
    "apps/.terraform"
    "apps/.terraform.lock.hcl"
)

for path in "${cleanup_paths[@]}"; do
    full_path="$SCRIPT_DIR/$path"
    if [ -e "$full_path" ]; then
        rm -rf "$full_path"
        info "Removed: $full_path"
    fi
done

# Clean generated files
rm -f "$SCRIPT_DIR"/infra/cloud-init-*.yaml 2>/dev/null || true
rm -f "$SCRIPT_DIR"/infra/haproxy_*.cfg 2>/dev/null || true
rm -f "$SCRIPT_DIR"/apps/haproxy_ingress.cfg 2>/dev/null || true

# Clean temp and kubeconfig
rm -f /tmp/hosts_ip.txt 2>/dev/null || true
rm -f ~/.kube/config-multipass 2>/dev/null || true
rm -f "$SCRIPT_DIR"/infra/multipass.log 2>/dev/null || true
rm -f "$SCRIPT_DIR"/apps/multipass.log 2>/dev/null || true

ok "State files cleaned."

# Step 5: Remove network bridge alias
step "5/5" "Removing network bridge alias..."
K8S_BRIDGE=$(ifconfig -a 2>/dev/null | grep -B15 'member: en0' | grep '^bridge' | tail -1 | cut -d: -f1)
if [ -n "$K8S_BRIDGE" ] && ifconfig "$K8S_BRIDGE" 2>/dev/null | grep -q "inet 192.168.50.1 "; then
    info "Removing 192.168.50.1 alias from $K8S_BRIDGE (requires sudo)..."
    if sudo ifconfig "$K8S_BRIDGE" -alias 192.168.50.1 2>/dev/null; then
        ok "Bridge alias removed."
    else
        info "Could not remove alias (may need sudo)."
    fi
else
    info "No bridge alias found, skipping."
fi

# Verify
echo ""
info "Multipass status:"
multipass list 2>&1 || true

# Final status
log "=== destroy-cluster completed at $(date '+%Y-%m-%d %H:%M:%S') ==="

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN} Cluster destroyed.${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "  ${GRAY}Log: $LOG_FILE${NC}"
echo ""
