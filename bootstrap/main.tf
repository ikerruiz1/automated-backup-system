data "aws_caller_identity" "current" {}

# 1. S3 Bucket for Terraform Remote State (Fully automated)
resource "aws_s3_bucket" "tfstate" {
  bucket        = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate_versioning" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate_encryption" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate_block" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. KMS CMK for DynamoDB Terraform state lock
resource "aws_kms_key" "dynamo_cmk" {
  description             = "KMS CMK for DynamoDB Terraform state lock"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

# 2. DynamoDB Table for Terraform State Locking
resource "aws_dynamodb_table" "tflock" {
  name         = "${var.project_name}-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamo_cmk.arn
  }
}

# 3. GitHub OIDC Identity Provider in AWS (Automated)
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # GitHub Actions OIDC thumbprint standard
}

# 4. IAM Role for GitHub Actions (Assumed via OIDC securely)
resource "aws_iam_role" "github_actions_role" {
  name = "github-actions-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_org}/${var.github_repo}:*",
              "repo:${var.github_org}@*/${var.github_repo}@*:*"
            ]
          }
        }
      }
    ]
  })
}

# 5. Administrator Access Policy attached to GitHub Actions Role (for full automation)

resource "aws_iam_role_policy_attachment" "admin_attachment" {
  # checkov:skip=CKV_AWS_274: "Bootstrap role requires administrator access to deploy entire infrastructure"
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Outputs needed to configure the main project backend
output "terraform_state_bucket" {
  value       = aws_s3_bucket.tfstate.id
  description = "Name of the S3 bucket created for Terraform state"
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_role.arn
  description = "ARN of the IAM role to be used in GitHub Actions OIDC"
}
