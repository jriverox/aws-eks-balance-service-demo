#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh
# Creates AWS resources required for Terraform remote state
# Resources: S3 bucket + DynamoDB table
# Usage: ./scripts/bootstrap.sh
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
# Validate AWS CLI is configured
# -----------------------------------------------------------------------------
log_info "Validating AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
  log_error "AWS credentials not configured or invalid."
  log_error "Run: aws configure"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log_info "AWS Account: ${ACCOUNT_ID} | Region: ${AWS_REGION}"

# -----------------------------------------------------------------------------
# Create S3 Bucket
# -----------------------------------------------------------------------------
log_info "Creating S3 bucket: ${S3_BUCKET}..."

if aws s3api head-bucket --bucket "${S3_BUCKET}" 2>/dev/null; then
  log_warn "S3 bucket '${S3_BUCKET}' already exists. Skipping creation."
else
  aws s3api create-bucket \
    --bucket "${S3_BUCKET}" \
    --region "${AWS_REGION}" \
    --create-bucket-configuration LocationConstraint="${AWS_REGION}" 2>/dev/null || \
  aws s3api create-bucket \
    --bucket "${S3_BUCKET}" \
    --region "${AWS_REGION}"

  log_info "Enabling versioning on S3 bucket..."
  aws s3api put-bucket-versioning \
    --bucket "${S3_BUCKET}" \
    --versioning-configuration Status=Enabled

  log_info "Enabling server-side encryption on S3 bucket..."
  aws s3api put-bucket-encryption \
    --bucket "${S3_BUCKET}" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }]
    }'

  log_info "Blocking public access on S3 bucket..."
  aws s3api put-public-access-block \
    --bucket "${S3_BUCKET}" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  log_info "S3 bucket '${S3_BUCKET}' created successfully."
fi

# -----------------------------------------------------------------------------
# Create DynamoDB Table
# -----------------------------------------------------------------------------
log_info "Creating DynamoDB table: ${DYNAMODB_TABLE}..."

if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}" &>/dev/null; then
  log_warn "DynamoDB table '${DYNAMODB_TABLE}' already exists. Skipping creation."
else
  aws dynamodb create-table \
    --table-name "${DYNAMODB_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}"

  log_info "Waiting for DynamoDB table to become active..."
  aws dynamodb wait table-exists \
    --table-name "${DYNAMODB_TABLE}" \
    --region "${AWS_REGION}"

  log_info "DynamoDB table '${DYNAMODB_TABLE}' created successfully."
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
log_info "Bootstrap completed successfully."
log_info "S3 Bucket:       ${S3_BUCKET}"
log_info "DynamoDB Table:  ${DYNAMODB_TABLE}"
log_info "Region:          ${AWS_REGION}"
echo ""
log_info "You can now run: cd terraform/environments/dev && terraform init"
