#!/usr/bin/env bash
# =============================================================================
# cleanup.sh
# Removes AWS bootstrap resources created by bootstrap.sh
# WARNING: Run AFTER terraform destroy
# Usage: ./scripts/cleanup.sh
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
AWS_REGION="us-east-1"
S3_BUCKET="jrx-aws-eks-balance-tfstate"
DYNAMODB_TABLE="jrx-aws-eks-balance-tfstate-lock"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------------------------------------------------------
# Safety confirmation
# -----------------------------------------------------------------------------
echo ""
log_warn "WARNING: This will permanently delete the following AWS resources:"
log_warn "  ECR Images:     balance-dev-balance-service, balance-dev-balance-gateway"
log_warn "  S3 Bucket:      ${S3_BUCKET} (including ALL versions)"
log_warn "  DynamoDB Table: ${DYNAMODB_TABLE}"
echo ""
log_warn "Make sure you have run './scripts/k8s_cleanup.sh' and 'terraform destroy' before proceeding."
echo ""
read -rp "Type 'yes' to confirm: " CONFIRMATION

if [ "${CONFIRMATION}" != "yes" ]; then
  log_info "Teardown cancelled."
  exit 0
fi

# -----------------------------------------------------------------------------
# Validate AWS credentials
# -----------------------------------------------------------------------------
log_info "Validating AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
  log_error "AWS credentials not configured or invalid."
  exit 1
fi

# -----------------------------------------------------------------------------
# Delete ECR Images
# Removes all images from ECR repositories before terraform destroy
# -----------------------------------------------------------------------------
ECR_REPOSITORIES=(
  "balance-dev-balance-service"
  "balance-dev-balance-gateway"
)

log_info "Cleaning up ECR repositories..."
for REPO in "${ECR_REPOSITORIES[@]}"; do
  if aws ecr describe-repositories --repository-names "${REPO}" --region "${AWS_REGION}" &>/dev/null; then
    log_info "Deleting all images from ECR repository: ${REPO}..."

    IMAGE_IDS=$(aws ecr list-images \
      --repository-name "${REPO}" \
      --region "${AWS_REGION}" \
      --query 'imageIds[*]' \
      --output json 2>/dev/null)

    if [ "${IMAGE_IDS}" != "[]" ] && [ -n "${IMAGE_IDS}" ]; then
      aws ecr batch-delete-image \
        --repository-name "${REPO}" \
        --region "${AWS_REGION}" \
        --image-ids "${IMAGE_IDS}" >/dev/null
      log_info "Images deleted from ${REPO}."
    else
      log_warn "No images found in ${REPO}. Skipping."
    fi
  else
    log_warn "ECR repository '${REPO}' not found. Skipping."
  fi
done

# -----------------------------------------------------------------------------
# Delete S3 Bucket
# -----------------------------------------------------------------------------
if aws s3api head-bucket --bucket "${S3_BUCKET}" 2>/dev/null; then

  log_info "Removing all objects from S3 bucket: ${S3_BUCKET}..."
  aws s3 rm "s3://${S3_BUCKET}" --recursive 2>/dev/null || true

  log_info "Removing all object versions..."
  VERSIONS=$(aws s3api list-object-versions \
    --bucket "${S3_BUCKET}" \
    --query 'Versions[].{Key:Key,VersionId:VersionId}' \
    --output json 2>/dev/null)

  if [ "${VERSIONS}" != "null" ] && [ "${VERSIONS}" != "[]" ] && [ -n "${VERSIONS}" ]; then
    DELETE_PAYLOAD=$(echo "${VERSIONS}" | jq '{Objects: .}')
    aws s3api delete-objects \
      --bucket "${S3_BUCKET}" \
      --delete "${DELETE_PAYLOAD}" >/dev/null
  fi

  log_info "Removing all delete markers..."
  MARKERS=$(aws s3api list-object-versions \
    --bucket "${S3_BUCKET}" \
    --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
    --output json 2>/dev/null)

  if [ "${MARKERS}" != "null" ] && [ "${MARKERS}" != "[]" ] && [ -n "${MARKERS}" ]; then
    DELETE_PAYLOAD=$(echo "${MARKERS}" | jq '{Objects: .}')
    aws s3api delete-objects \
      --bucket "${S3_BUCKET}" \
      --delete "${DELETE_PAYLOAD}" >/dev/null
  fi

  log_info "Deleting S3 bucket: ${S3_BUCKET}..."
  aws s3api delete-bucket \
    --bucket "${S3_BUCKET}" \
    --region "${AWS_REGION}"

  log_info "S3 bucket '${S3_BUCKET}' deleted successfully."
else
  log_warn "S3 bucket '${S3_BUCKET}' not found. Skipping."
fi

# -----------------------------------------------------------------------------
# Delete DynamoDB Table
# -----------------------------------------------------------------------------
log_info "Deleting DynamoDB table: ${DYNAMODB_TABLE}..."

if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}" &>/dev/null; then
  aws dynamodb delete-table \
    --table-name "${DYNAMODB_TABLE}" \
    --region "${AWS_REGION}"

  log_info "Waiting for DynamoDB table to be deleted..."
  aws dynamodb wait table-not-exists \
    --table-name "${DYNAMODB_TABLE}" \
    --region "${AWS_REGION}"

  log_info "DynamoDB table '${DYNAMODB_TABLE}' deleted successfully."
else
  log_warn "DynamoDB table '${DYNAMODB_TABLE}' not found. Skipping."
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
log_info "Teardown completed successfully."