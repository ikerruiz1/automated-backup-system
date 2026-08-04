#!/bin/bash
set -e

# 1. Validations
if [ ! -f "terraform.tfvars" ]; then
    echo "Error: The terraform.tfvars file does not exist. Create one from terraform.tfvars.example."
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed or configured."
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo "Error: Terraform is not installed."
    exit 1
fi

# 2. Local variables extraction using awk
PROJECT_NAME=$(grep -E "^project_name\s*=" terraform.tfvars | awk -F '"' '{print $2}')
AWS_REGION=$(grep -E "^aws_region\s*=" terraform.tfvars | awk -F '"' '{print $2}')
ENVIRONMENT=$(grep -E "^environment\s*=" terraform.tfvars | awk -F '"' '{print $2}')
NOTIFICATION_EMAIL=$(grep -E "^notification_email\s*=" terraform.tfvars | awk -F '"' '{print $2}')
BACKUP_RETENTION=$(grep -E "^backup_retention_days\s*=" terraform.tfvars | awk -F '=' '{print $2}' | tr -d ' ')
MIN_RETENTION=$(grep -E "^vault_lock_min_retention_days\s*=" terraform.tfvars | awk -F '=' '{print $2}' | tr -d ' ')
MAX_RETENTION=$(grep -E "^vault_lock_max_retention_days\s*=" terraform.tfvars | awk -F '=' '{print $2}' | tr -d ' ')

# 3. Base infrastructure deployment (Bootstrap)
cd bootstrap
cp ../terraform.tfvars terraform.tfvars
terraform init -input=false
terraform apply -auto-approve -input=false

STATE_BUCKET=$(terraform output -raw terraform_state_bucket)
OIDC_ROLE_ARN=$(terraform output -raw github_actions_role_arn)
cd ..

# 4. Secrets Injection (GitHub Actions)
gh secret set AWS_ROLE_ARN --body "${OIDC_ROLE_ARN}"
gh secret set NOTIFICATION_EMAIL --body "${NOTIFICATION_EMAIL}"

# 5. Environment Variables Injection (GitHub Actions)
gh variable set TF_STATE_BUCKET --body "${STATE_BUCKET}"
gh variable set TF_DYNAMODB_TABLE --body "${PROJECT_NAME}-tflock"
gh variable set AWS_REGION --body "${AWS_REGION}"
gh variable set PROJECT_NAME --body "${PROJECT_NAME}"
gh variable set ENVIRONMENT --body "${ENVIRONMENT}"
gh variable set BACKUP_RETENTION_DAYS --body "${BACKUP_RETENTION}"
gh variable set VAULT_LOCK_MIN_RETENTION_DAYS --body "${MIN_RETENTION}"
gh variable set VAULT_LOCK_MAX_RETENTION_DAYS --body "${MAX_RETENTION}"

# 6. Pipeline execution
git add .
git commit -m "chore: automated deployment triggered by platform script"
git push -u origin main