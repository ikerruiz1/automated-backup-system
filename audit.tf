# AWS Config Configuration Recorder
resource "aws_config_configuration_recorder" "recorder" {
  name     = "${var.project_name}-config-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

# AWS Config Delivery Channel for compliance logs
resource "aws_config_delivery_channel" "channel" {
  name           = "${var.project_name}-config-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config_bucket.id

  depends_on = [
    aws_config_configuration_recorder.recorder,
    aws_iam_role_policy.config_s3_policy,
    aws_iam_role_policy_attachment.config_role_policy
  ]
}

# Enable the Configuration Recorder
resource "aws_config_configuration_recorder_status" "recorder_status" {
  name       = aws_config_configuration_recorder.recorder.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.channel]
}

# S3 Bucket for AWS Config logs
resource "aws_s3_bucket" "config_bucket" {
  bucket        = "${var.project_name}-config-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

# Enable versioning to comply with CKV_AWS_21
resource "aws_s3_bucket_versioning" "config_bucket_versioning" {
  bucket = aws_s3_bucket.config_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable access logging pointing to log_bucket to comply with CKV_AWS_18
resource "aws_s3_bucket_logging" "config_bucket_logging" {
  bucket        = aws_s3_bucket.config_bucket.id
  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "config-logs/"

  depends_on = [aws_s3_bucket_policy.log_bucket_policy]
}

# S3 Bucket Ownership Controls for Config
resource "aws_s3_bucket_ownership_controls" "config_bucket_ownership" {
  bucket = aws_s3_bucket.config_bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# S3 Bucket Public Access Block for Config
resource "aws_s3_bucket_public_access_block" "config_bucket_block" {
  bucket                  = aws_s3_bucket.config_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for AWS Config
resource "aws_iam_role" "config_role" {
  name = "${var.project_name}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS Managed Policy for Config
resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Custom policy to allow AWS Config to write to S3
resource "aws_iam_role_policy" "config_s3_policy" {
  name = "${var.project_name}-config-s3-policy"
  role = aws_iam_role.config_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.config_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
      },
      {
        Action = [
          "s3:GetBucketAcl"
        ]
        Effect   = "Allow"
        Resource = aws_s3_bucket.config_bucket.arn
      }
    ]
  })
}

# Data source to get current AWS Account ID
data "aws_caller_identity" "current" {}

# AWS Backup Framework for Audit Manager and Compliance
resource "aws_backup_framework" "compliance_framework" {
  name        = "${replace(var.project_name, "-", "_")}_compliance_framework"
  description = "Enterprise compliance framework for backup governance"

  depends_on = [
    aws_config_configuration_recorder.recorder,
    aws_config_configuration_recorder_status.recorder_status,
    aws_config_delivery_channel.channel
  ]

  control {
    name = "BACKUP_RECOVERY_POINT_ENCRYPTED"
  }

  control {
    name = "BACKUP_RESOURCES_PROTECTED_BY_BACKUP_PLAN"
    scope {
      compliance_resource_types = [
        "EBS",
        "RDS",
        "S3"
      ]
    }
  }

  control {
    name = "BACKUP_RESOURCES_PROTECTED_BY_BACKUP_VAULT_LOCK"
    input_parameter {
      name  = "maxRetentionDays"
      value = tostring(var.vault_lock_max_retention_days)
    }
    input_parameter {
      name  = "minRetentionDays"
      value = tostring(var.vault_lock_min_retention_days)
    }
    scope {
      compliance_resource_types = [
        "EBS"
      ]
    }
  }

  tags = {
    Name = "${var.project_name}-compliance-framework"
  }
}
