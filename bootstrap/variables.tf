variable "aws_region" {
  type        = string
  description = "AWS Region for bootstrap resources"
  default     = "eu-west-1"
}

variable "project_name" {
  type        = string
  description = "Project name prefix"
  default     = "enterprise-backup-system"
}

variable "github_org" {
  type        = string
  description = "GitHub Organization or Username"
  default     = "your-github-username"
}

variable "github_repo" {
  type        = string
  description = "GitHub Repository Name"
  default     = "your-repo-name"
}

variable "environment" {
  type        = string
  description = "Ignored in bootstrap. Prevents warnings from copied tfvars."
  default     = ""
}

variable "notification_email" {
  type        = string
  description = "Ignored in bootstrap. Prevents warnings from copied tfvars."
  default     = ""
}

variable "backup_retention_days" {
  type        = number
  description = "Ignored in bootstrap. Prevents warnings from copied tfvars."
  default     = 0
}

variable "vault_lock_min_retention_days" {
  type        = number
  description = "Ignored in bootstrap. Prevents warnings from copied tfvars."
  default     = 0
}

variable "vault_lock_max_retention_days" {
  type        = number
  description = "Ignored in bootstrap. Prevents warnings from copied tfvars."
  default     = 0
}
