#!/usr/bin/env bash
# =============================================================================
# validate_prerequisites.sh
# Comprueba que todas las herramientas necesarias estén instaladas y configuradas correctamente
# Uso: ./scripts/validate_prerequisites.sh
# =============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }

ERRORS=0

check() {
  local name=$1
  local cmd=$2
  local version_cmd=$3

  if command -v "${cmd}" &>/dev/null; then
    local version
    version=$(eval "${version_cmd}" 2>&1 | head -1)
    log_success "${name}: ${version}"
  else
    log_error "${name}: NOT FOUND — please install it before proceeding."
    ERRORS=$((ERRORS + 1))
  fi
}

echo ""
echo "==========================================="
echo "  Validación de los requisitos previos"
echo "  aws-eks-balance-service-demo"
echo "==========================================="
echo ""

# -----------------------------------------------------------------------------
# Tool checks
# -----------------------------------------------------------------------------
check "AWS CLI"   "aws"       "aws --version"
check "Docker"    "docker"    "docker --version"
check "kubectl"   "kubectl"   "kubectl version --client --short 2>/dev/null || kubectl version --client"
check "Terraform" "terraform" "terraform version | head -1"
check "Poetry"    "poetry"    "poetry --version"
check "Python"    "python3"   "python3 --version"
check "Git"       "git"       "git --version"

echo ""

# -----------------------------------------------------------------------------
# Comprobación de credenciales de AWS
# -----------------------------------------------------------------------------
log_info "Checking AWS credentials..."
if aws sts get-caller-identity &>/dev/null; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  AWS_REGION=$(aws configure get region || echo "not set")
  log_success "AWS credentials valid — Account: ${ACCOUNT_ID} | Region: ${AWS_REGION}"
else
  log_error "AWS credentials not configured or invalid. Run: aws configure"
  ERRORS=$((ERRORS + 1))
fi

# -----------------------------------------------------------------------------
# Docker daemon check
# -----------------------------------------------------------------------------
log_info "Checking Docker daemon..."
if docker info &>/dev/null; then
  log_success "Docker daemon is running."
else
  log_error "Docker daemon is not running. Please start Docker."
  ERRORS=$((ERRORS + 1))
fi

# -----------------------------------------------------------------------------
# Python version check (minimum 3.11)
# -----------------------------------------------------------------------------
log_info "Checking Python version..."
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
REQUIRED_MAJOR=3
REQUIRED_MINOR=11

MAJOR=$(echo "${PYTHON_VERSION}" | cut -d. -f1)
MINOR=$(echo "${PYTHON_VERSION}" | cut -d. -f2)

if [ "${MAJOR}" -gt "${REQUIRED_MAJOR}" ] || \
   ([ "${MAJOR}" -eq "${REQUIRED_MAJOR}" ] && [ "${MINOR}" -ge "${REQUIRED_MINOR}" ]); then
  log_success "Python version ${PYTHON_VERSION} meets requirement (>= 3.11)"
else
  log_error "Python version ${PYTHON_VERSION} does not meet requirement (>= 3.11)"
  ERRORS=$((ERRORS + 1))
fi

# -----------------------------------------------------------------------------
# Mostrar Resumen
# -----------------------------------------------------------------------------
echo ""
echo "==========================================="
if [ "${ERRORS}" -eq 0 ]; then
  log_success "All prerequisites validated successfully."
  echo ""
  log_info "Next step: ./scripts/bootstrap.sh"
else
  log_error "${ERRORS} prerequisite(s) failed. Please resolve the issues above."
  exit 1
fi
echo "==========================================="
echo ""
