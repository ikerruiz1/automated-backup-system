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

# 3. Automatic Backend initialization
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

# 5. Destroy workload infrastructure
echo "Destroying workload infrastructure..."
terraform destroy -auto-approve -lock=false

# 6. Automate complete cleanup of the state bucket BEFORE Terraform tries to delete it in bootstrap
echo "Automating full cleanup of S3 state bucket..."
if aws s3 ls "s3://${STATE_BUCKET}" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "State bucket does not exist or is already deleted."
else
    echo "Removing all current objects..."
    aws s3 rm "s3://${STATE_BUCKET}" --recursive || true

    echo "Removing all object versions and delete markers..."
    VERSIONS=$(aws s3api list-object-versions --bucket "${STATE_BUCKET}" --output=json --query='{Objects: ToArray(Versions[].{Key:Key,VersionId:VersionId}), DeleteMarkers: ToArray(DeleteMarkers[].{Key:Key,VersionId:VersionId})} | [?(length(Objects) > `0` || length(DeleteMarkers) > `0`)]' 2>/dev/null || echo "")
    
    if [ -n "$VERSIONS" ] && [ "$VERSIONS" != "[]" ]; then
        aws s3api delete-objects --bucket "${STATE_BUCKET}" --delete "$VERSIONS" 2>/dev/null || true
    fi
fi

# 7. Destroy base infrastructure (Bootstrap) decoupling the bucket first to prevent BucketNotEmpty errors
echo "Destroying base infrastructure (Bootstrap)..."
cd bootstrap
terraform init -input=false >/dev/null 2>&1 || true
terraform state rm aws_s3_bucket.tfstate 2>/dev/null || true
terraform destroy -auto-approve
cd ..

# Final forced removal of the bucket if it remains orphaned
aws s3 rb "s3://${STATE_BUCKET}" --force 2>/dev/null || true

echo "=== TEARDOWN COMPLETED SUCCESSFULLY ==="
echo "Note: The AWS Backup vault remains in AWS due to the mandatory WORM retention policy."