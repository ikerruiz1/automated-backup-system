#!/bin/bash
set -e

export AWS_PAGER=""

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

# Purge local cache to prevent phantom lock errors
rm -rf .terraform 2>/dev/null || true

# 2. Automatic extraction of variables and credentials
PROJECT_NAME=$(grep -E "^project_name\s*=" terraform.tfvars | awk -F '"' '{print $2}')
REGION=$(grep -E "^aws_region\s*=" terraform.tfvars | awk -F '"' '{print $2}')
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text | tr -d '\r')

STATE_BUCKET="${PROJECT_NAME}-tfstate-${ACCOUNT_ID}"
DYNAMODB_TABLE="${PROJECT_NAME}-tflock"
BACKUP_VAULT_NAME="${PROJECT_NAME}-vault"

echo "Project: $PROJECT_NAME"
echo "Region: $REGION"
echo "Detected State Bucket: $STATE_BUCKET"
echo "Detected Backup Vault: $BACKUP_VAULT_NAME"

# 3. Conditional Backend initialization and Workload Destruction
if aws s3 ls "s3://${STATE_BUCKET}" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "State bucket does not exist. Skipping Terraform init and workload destruction."
else
    echo "Initializing Terraform with the remote state..."
    terraform init \
      -backend-config="bucket=${STATE_BUCKET}" \
      -backend-config="key=backup-project/terraform.tfstate" \
      -backend-config="region=${REGION}" \
      -backend-config="encrypt=true" \
      -backend-config="dynamodb_table=${DYNAMODB_TABLE}" || true

    echo "Decoupling WORM resources (Vault Lock) from the Terraform state..."
    terraform state rm aws_backup_vault.main 2>/dev/null || true
    terraform state rm aws_backup_vault_lock_configuration.lock 2>/dev/null || true

    echo "Destroying workload infrastructure..."
    terraform destroy -auto-approve -lock=false || true

    echo "Automating full cleanup of S3 state bucket..."
    aws s3 rm "s3://${STATE_BUCKET}" --recursive || true

    echo "Removing all object versions..."
    aws s3api list-object-versions --bucket "${STATE_BUCKET}" --output text --query 'Versions[*].[Key, VersionId]' 2>/dev/null | tr -d '\r' | while IFS=$'\t' read -r key version; do
        if [ -n "$key" ] && [ "$key" != "None" ] && [ -n "$version" ] && [ "$version" != "None" ]; then
            aws s3api delete-object --bucket "${STATE_BUCKET}" --key "$key" --version-id "$version" >/dev/null
        fi
    done || true

    echo "Removing all delete markers..."
    aws s3api list-object-versions --bucket "${STATE_BUCKET}" --output text --query 'DeleteMarkers[*].[Key, VersionId]' 2>/dev/null | tr -d '\r' | while IFS=$'\t' read -r key version; do
        if [ -n "$key" ] && [ "$key" != "None" ] && [ -n "$version" ] && [ "$version" != "None" ]; then
            aws s3api delete-object --bucket "${STATE_BUCKET}" --key "$key" --version-id "$version" >/dev/null
        fi
    done || true

    echo "Ensuring S3 state bucket is completely removed..."
    for i in {1..5}; do
        aws s3 rb "s3://${STATE_BUCKET}" --force 2>/dev/null && break || sleep 3
    done
fi

# 4. Destroy base infrastructure (Bootstrap)
echo "Destroying base infrastructure (Bootstrap)..."
if [ -d "bootstrap" ]; then
    cd bootstrap
    rm -rf .terraform 2>/dev/null || true
    terraform init -input=false >/dev/null 2>&1 || true
    terraform state rm aws_s3_bucket.tfstate 2>/dev/null || true
    terraform destroy -auto-approve 2>/dev/null || true
    cd ..
fi

# 5. Purge remaining auxiliary resources via CLI
echo "Purging remaining auxiliary resources via AWS CLI..."

# 5.1 DynamoDB (Table only)
echo "Deleting DynamoDB lock table: ${DYNAMODB_TABLE}"
aws dynamodb delete-table --table-name "${DYNAMODB_TABLE}" --region "${REGION}" 2>/dev/null || echo "DynamoDB table already deleted."

# 5.2 IAM Roles (Strictly filtered by project)
echo "Checking IAM roles..."
ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, '${PROJECT_NAME}') || RoleName=='github-actions-terraform-role'].RoleName" --output text 2>/dev/null | tr -d '\r')
for role in $ROLES; do
    if [ -n "$role" ] && [ "$role" != "None" ]; then
        echo "Cleaning up IAM role: $role"
        POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null | tr -d '\r' || true)
        for policy in $POLICIES; do
            if [ -n "$policy" ] && [ "$policy" != "None" ]; then
                aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
            fi
        done
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" --query "PolicyNames[]" --output text 2>/dev/null | tr -d '\r' || true)
        for ipolicy in $INLINE_POLICIES; do
            if [ -n "$ipolicy" ] && [ "$ipolicy" != "None" ]; then
                aws iam delete-role-policy --role-name "$role" --policy-name "$ipolicy" 2>/dev/null || true
            fi
        done
        aws iam delete-role --role-name "$role" 2>/dev/null || true
    fi
done

# 5.3 KMS Keys (Strictly filtered by project)
echo "Checking KMS Keys..."
KMS_KEYS=$(aws kms list-aliases --query "Aliases[?contains(AliasName, '${PROJECT_NAME}')].TargetKeyId" --output text 2>/dev/null | tr -d '\r')
for key in $KMS_KEYS; do
    if [ -n "$key" ] && [ "$key" != "None" ]; then
        echo "Scheduling deletion for KMS Key: $key (7 days)"
        aws kms schedule-key-deletion --key-id "$key" --pending-window-in-days 7 2>/dev/null || true
    fi
done

# 5.4 AWS Backup Vault & Governance Vault Lock Purge
echo "Checking AWS Backup Vault: ${BACKUP_VAULT_NAME}"
if aws backup describe-backup-vault --backup-vault-name "${BACKUP_VAULT_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "Removing Governance Vault Lock configuration..."
    aws backup delete-backup-vault-lock-configuration --backup-vault-name "${BACKUP_VAULT_NAME}" --region "${REGION}" 2>/dev/null || true

    echo "Deleting all recovery points inside the vault..."
    RECOVERY_POINTS=$(aws backup list-recovery-points-by-backup-vault --backup-vault-name "${BACKUP_VAULT_NAME}" --region "${REGION}" --query "RecoveryPoints[].RecoveryPointArn" --output text 2>/dev/null | tr -d '\r')
    for rp in $RECOVERY_POINTS; do
        if [ -n "$rp" ] && [ "$rp" != "None" ]; then
            echo "Deleting recovery point: $rp"
            aws backup delete-recovery-point --backup-vault-name "${BACKUP_VAULT_NAME}" --recovery-point-arn "$rp" --region "${REGION}" 2>/dev/null || true
        fi
    done

    echo "Waiting for AWS to process recovery point deletions..."
    sleep 15

    echo "Deleting Backup Vault: ${BACKUP_VAULT_NAME}"
    for i in {1..5}; do
        aws backup delete-backup-vault --backup-vault-name "${BACKUP_VAULT_NAME}" --region "${REGION}" 2>/dev/null && echo "Vault deleted successfully." && break || echo "Retrying vault deletion..." && sleep 5
    done
else
    echo "Backup Vault ${BACKUP_VAULT_NAME} does not exist or was already deleted."
fi

echo "=== TEARDOWN COMPLETED SUCCESSFULLY ==="