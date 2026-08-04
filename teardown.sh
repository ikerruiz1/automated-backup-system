#!/bin/bash
set -e

echo "=== STARTING SECURE TEARDOWN ==="

# 1. Pre-flight validations
if [ ! -f "terraform.tfvars" ]; then
    echo "Error: The terraform.tfvars file does not exist in the root directory."
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo "Error: Terraform is not installed."
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed."
    exit 1
fi

# 2. Automatic extraction of variables and credentials
PROJECT_NAME=$(grep -E "^project_name\s*=" terraform.tfvars | awk -F '"' '{print $2}')
REGION=$(grep -E "^aws_region\s*=" terraform.tfvars | awk -F '"' '{print $2}')
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

STATE_BUCKET="${PROJECT_NAME}-tfstate-${ACCOUNT_ID}"
DYNAMODB_TABLE="${PROJECT_NAME}-tflock"

echo "Project: $PROJECT_NAME"
echo "Region: $REGION"
echo "Detected State Bucket: $STATE_BUCKET"

# 3. Automatic Backend initialization (Resolves the backend.conf issue)
echo "Initializing Terraform with the remote state..."
terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="key=backup-project/terraform.tfstate" \
  -backend-config="region=${REGION}" \
  -backend-config="encrypt=true" \
  -backend-config="dynamodb_table=${DYNAMODB_TABLE}"

# 4. Decouple immutable resources from state to prevent Vault Lock errors
echo "Decoupling WORM resources (Vault Lock) from the Terraform state..."
terraform state rm aws_backup_vault.main 2>/dev/null || true
terraform state rm aws_backup_vault_lock_configuration.lock 2>/dev/null || true

# 5. Destroy workload infrastructure (VPC, EC2, RDS, S3, etc.)
echo "Destroying workload infrastructure..."
terraform destroy -auto-approve

# 6. Destroy base infrastructure (Bootstrap: state S3 and OIDC)
echo "Destroying base infrastructure (Bootstrap)..."
cd bootstrap
terraform init -input=false
terraform destroy -auto-approve
cd ..

echo "=== TEARDOWN COMPLETED SUCCESSFULLY ==="
echo "Note: The AWS Backup vault remains in AWS due to the mandatory WORM retention policy."