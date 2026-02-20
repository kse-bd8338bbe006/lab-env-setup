#!/bin/bash
#
# Creates a Multipass K8s cluster on macOS and deploys applications with Terraform.
#
# Orchestrates the full cluster lifecycle:
#   1. Pre-flight checks (multipass, terraform, SSH key)
#   2. Clean stale files from previous runs
#   3. Infrastructure deployment (VMs, K8s bootstrap, kubeconfig)
#   4. Network bridge setup (requires sudo)
#   5. Application deployment (ingress, monitoring, ArgoCD, Vault)
#
# All output is logged to logs/create-cluster_<timestamp>.log for troubleshooting.
#

set -euo pipefail

# -- Configuration ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/create-cluster_$TIMESTAMP.log"

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

fail() {
    echo -e "  ${RED}[FAIL]${NC} $1"
    log "$1" "FAIL"
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
    if "$@" 2>&1 | tee -a "$LOG_FILE"; then
        log "Command succeeded"
        return 0
    else
        local code=$?
        log "Command failed with exit code $code" "ERROR"
        return $code
    fi
}

# -- Main ----------------------------------------------------------------------

cd "$SCRIPT_DIR"

# Initialize log
echo "=== create-cluster started at $(date '+%Y-%m-%d %H:%M:%S') ===" > "$LOG_FILE"
log "Shell: $SHELL ($BASH_VERSION)"
log "Working directory: $SCRIPT_DIR"

echo -e "${WHITE}============================================${NC}"
echo -e "${WHITE} macOS K8s Cluster Setup (Multipass)${NC}"
echo -e "${WHITE}============================================${NC}"
echo -e "  ${GRAY}Log file: $LOG_FILE${NC}"

# Step 1: Pre-flight checks
step "1/7" "Running pre-flight checks..."

if ! command -v multipass &>/dev/null; then
    fail "multipass not found in PATH"
    exit 1
fi
log "multipass: $(multipass version 2>/dev/null | head -1)"
ok "multipass found."

if ! command -v terraform &>/dev/null; then
    fail "terraform not found in PATH"
    exit 1
fi
log "terraform: $(terraform --version 2>/dev/null | head -1)"
ok "terraform found."

SSH_KEY_PATH="$HOME/.ssh/kse_ci_cd_sec_id_rsa"
if [ ! -f "$SSH_KEY_PATH" ]; then
    info "SSH key not found, generating..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" >> "$LOG_FILE" 2>&1
    ok "SSH key pair generated: $SSH_KEY_PATH"
else
    ok "SSH key found."
fi

# Step 2: Clean stale files
step "2/7" "Cleaning stale files from previous runs..."
rm -f /tmp/hosts_ip.txt 2>/dev/null || true
rm -f ~/.kube/config-multipass 2>/dev/null || true
ok "Stale files cleaned."

# Step 3: Initialize infrastructure Terraform
step "3/7" "Initializing infrastructure Terraform..."
if ! run_logged "terraform init (infra)" terraform -chdir=infra init; then
    fail "terraform init (infra) failed. See log: $LOG_FILE"
    exit 1
fi
ok "Infrastructure Terraform initialized."

# Step 4: Deploy infrastructure
step "4/7" "Deploying infrastructure with Terraform (VMs, K8s cluster, kubeconfig)..."
info "This will take several minutes while VMs are created and K8s is bootstrapped."
if ! run_logged "terraform apply (infra)" terraform -chdir=infra apply -auto-approve; then
    fail "terraform apply (infra) failed. See log: $LOG_FILE"
    exit 1
fi
ok "Infrastructure deployed (cluster ready, kubeconfig available)."

# Step 5: Network bridge setup
step "5/7" "Setting up network bridge (requires sudo)..."
info "Adding gateway alias so macOS host can reach VMs on static IPs."
SETUP_NETWORK="$SCRIPT_DIR/setup-network.sh"
if [ -f "$SETUP_NETWORK" ]; then
    if sudo bash "$SETUP_NETWORK" >> "$LOG_FILE" 2>&1; then
        ok "Network bridge configured."
    else
        fail "Network setup failed. See log: $LOG_FILE"
        info "You can run it manually: sudo bash $SETUP_NETWORK"
        info "Then re-run this script or run: cd apps && terraform init && terraform apply -auto-approve"
        exit 1
    fi
else
    fail "setup-network.sh not found at $SETUP_NETWORK"
    exit 1
fi

# Verify connectivity
if ping -c 1 -t 3 192.168.50.10 &>/dev/null; then
    ok "Connectivity to HAProxy (192.168.50.10) verified."
else
    fail "Cannot reach 192.168.50.10. Network bridge may not be working."
    exit 1
fi

# Step 6: Initialize applications Terraform
step "6/7" "Initializing applications Terraform..."
if ! run_logged "terraform init (apps)" terraform -chdir=apps init; then
    fail "terraform init (apps) failed. See log: $LOG_FILE"
    exit 1
fi
ok "Applications Terraform initialized."

# Step 7: Deploy applications
step "7/7" "Deploying applications with Terraform (ingress, monitoring, ArgoCD, Vault)..."
if ! run_logged "terraform apply (apps)" terraform -chdir=apps apply -auto-approve; then
    fail "terraform apply (apps) failed. See log: $LOG_FILE"
    exit 1
fi
ok "Applications deployed."

# Final status
log "=== create-cluster completed at $(date '+%Y-%m-%d %H:%M:%S') ==="

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN} Cluster deployed successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  ${WHITE}Cluster:     kubectl --kubeconfig ~/.kube/config-multipass get nodes${NC}"
echo -e "  ${WHITE}ArgoCD:      http://argocd.192.168.50.10.nip.io${NC}"
echo -e "  ${WHITE}Grafana:     http://grafana.192.168.50.10.nip.io${NC}"
echo -e "  ${WHITE}Vault:       http://vault.192.168.50.10.nip.io${NC}"
echo -e "  ${WHITE}Prometheus:  http://prometheus.192.168.50.10.nip.io${NC}"
echo ""
echo -e "  ${WHITE}SSH:         multipass shell <vm-name>${NC}"
echo -e "  ${GRAY}Log:         $LOG_FILE${NC}"
echo ""
