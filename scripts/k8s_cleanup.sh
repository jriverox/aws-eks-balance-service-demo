#!/usr/bin/env bash
# =============================================================================
# k8s-cleanup.sh
# Removes Kubernetes resources and Helm releases before terraform destroy
# Usage: ./scripts/k8s-cleanup.sh
# =============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${REPO_ROOT}/k8s"

# -----------------------------------------------------------------------------
# Validate kubectl is configured
# -----------------------------------------------------------------------------
log_info "Validating kubectl connection..."
if ! kubectl cluster-info &>/dev/null; then
  log_error "kubectl is not configured or cannot reach the cluster."
  log_error "Run: aws eks update-kubeconfig --region us-east-1 --name balance-dev-cluster"
  exit 1
fi

log_info "Connected to cluster: $(kubectl config current-context)"

# -----------------------------------------------------------------------------
# Step 1 — Delete Kubernetes resources
# This triggers ALB deletion by the Load Balancer Controller
# -----------------------------------------------------------------------------
log_info "Deleting Kubernetes resources from k8s/..."
if kubectl delete -f "${K8S_DIR}/" 2>/dev/null; then
  log_info "Kubernetes resources deleted."
else
  log_warn "Some resources may not have existed. Continuing..."
fi

log_info "Waiting 60 seconds for ALB to be deleted by Load Balancer Controller..."
sleep 60

# -----------------------------------------------------------------------------
# Step 2 — Uninstall AWS Load Balancer Controller
# -----------------------------------------------------------------------------
log_info "Uninstalling AWS Load Balancer Controller..."
if helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null; then
  log_info "AWS Load Balancer Controller uninstalled."
else
  log_warn "AWS Load Balancer Controller was not installed. Skipping."
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
log_info "Kubernetes teardown completed successfully."
log_info "Next step: cd terraform/environments/dev && terraform destroy"