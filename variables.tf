variable "aws_region" {
  type        = string
  description = "AWS Region where the backup infrastructure will be deployed"
  default     = "eu-west-1"
}

variable "project_name" {
  type        = string
  description = "Project identifier name for resource tagging"
  default     = "enterprise-backup-system"
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g., production, staging)"
  default     = "production"
}

variable "notification_email" {
  type        = string
  description = "Email address to receive critical Amazon SNS alerts"
  default     = "ops-alerts@enterprise.com"
}


variable "github_org" {
  type        = string
  description = "GitHub organization or user that owns the repository"
}

variable "github_repo" {
  type        = string
  description = "Name of the GitHub repository"
}

variable "backup_retention_days" {
  type        = number
  description = "Number of days recovery points will be retained in the vault before expiring"
  default     = 30
}

variable "vault_lock_min_retention_days" {
  type        = number
  description = "Minimum immutable retention days required by Vault Lock (Compliance Mode)"
  default     = 15
}

variable "vault_lock_max_retention_days" {
  type        = number
  description = "Maximum immutable retention days required by Vault Lock (Compliance Mode)"
  default     = 365
}
