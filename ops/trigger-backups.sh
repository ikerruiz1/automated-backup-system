#!/bin/bash
set -e

echo "Retrieving resource identifiers from AWS..."

if [ ! -f "../terraform.tfvars" ]; then
    echo "Error: Run this script from the ops/ directory and ensure terraform.tfvars exists in the root."
    exit 1
fi

PROJECT_NAME=$(grep -E "^project_name\s*=" ../terraform.tfvars | awk -F '"' '{print $2}')
REGION=$(grep -E "^aws_region\s*=" ../terraform.tfvars | awk -F '"' '{print $2}')
RETENTION_DAYS=$(grep -E "^backup_retention_days\s*=" ../terraform.tfvars | tr -d ' ' | cut -d'=' -f2)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

VAULT_NAME="${PROJECT_NAME}-vault"
IAM_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-backup-service-role"
BUCKET_NAME="${PROJECT_NAME}-secure-data-${ACCOUNT_ID}"

INSTANCE_ID=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=${PROJECT_NAME}-app-server" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
    echo "Error: EC2 instance not found. Has the GitHub Actions pipeline finished?"
    exit 1
fi

echo "Starting AWS Backup jobs asynchronously..."

aws backup start-backup-job \
  --region "$REGION" \
  --backup-vault-name "$VAULT_NAME" \
  --resource-arn "arn:aws:s3:::${BUCKET_NAME}" \
  --iam-role-arn "$IAM_ROLE_ARN" \
  --lifecycle DeleteAfterDays="$RETENTION_DAYS" \
  > /dev/null
echo "- S3 Backup initiated."

aws backup start-backup-job \
  --region "$REGION" \
  --backup-vault-name "$VAULT_NAME" \
  --resource-arn "arn:aws:ec2:${REGION}:${ACCOUNT_ID}:instance/${INSTANCE_ID}" \
  --iam-role-arn "$IAM_ROLE_ARN" \
  --lifecycle DeleteAfterDays="$RETENTION_DAYS" \
  > /dev/null
echo "- EC2 Backup initiated."

aws backup start-backup-job \
  --region "$REGION" \
  --backup-vault-name "$VAULT_NAME" \
  --resource-arn "arn:aws:rds:${REGION}:${ACCOUNT_ID}:db:${PROJECT_NAME}-db" \
  --iam-role-arn "$IAM_ROLE_ARN" \
  --lifecycle DeleteAfterDays="$RETENTION_DAYS" \
  > /dev/null
echo "- RDS Backup initiated."

echo "Backup commands successfully sent to the AWS API."
echo "The EventBridge and SNS infrastructure will automatically email you upon completion."