# IAM Role for AWS Backup Service
resource "aws_iam_role" "backup_service_role" {
  name = "${var.project_name}-backup-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the official AWS managed policy for backups
resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# Attach the official AWS managed policy for restores
resource "aws_iam_role_policy_attachment" "restore_policy" {
  role       = aws_iam_role.backup_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Attach the official AWS managed policy for S3 backups
resource "aws_iam_role_policy_attachment" "backup_s3_policy" {
  role       = aws_iam_role.backup_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
}

# Attach the official AWS managed policy for S3 restores
resource "aws_iam_role_policy_attachment" "restore_s3_policy" {
  role       = aws_iam_role.backup_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore"
}

# Policy to allow AWS Backup to operate with the CMK and restore EC2 roles
resource "aws_iam_role_policy" "backup_kms_policy" {
  name = "${var.project_name}-backup-operations-policy"
  role = aws_iam_role.backup_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Effect   = "Allow"
        Resource = aws_kms_key.enterprise_cmk.arn
      },
      {
        Action = [
          "iam:PassRole"
        ]
        Effect   = "Allow"
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" : "ec2.amazonaws.com"
          }
        }
      }
    ]
  })
}
