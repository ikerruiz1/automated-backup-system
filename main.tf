# Regional AWS Backup Settings (Mandatory Opt-In for S3)
resource "aws_backup_region_settings" "settings" {
  resource_type_opt_in_preference = {
    "AWS::EC2::Instance"   = true
    "AWS::EC2::Volume"     = true
    "AWS::RDS::DBInstance" = true
    "AWS::S3::Bucket"      = true
  }
}

# Backup Vault
resource "aws_backup_vault" "main" {
  name        = "${var.project_name}-vault"
  kms_key_arn = aws_kms_key.enterprise_cmk.arn
}

# Vault Lock (WORM Immutability in Compliance Mode)
resource "aws_backup_vault_lock_configuration" "lock" {
  backup_vault_name  = aws_backup_vault.main.name
  min_retention_days = var.vault_lock_min_retention_days
  max_retention_days = var.vault_lock_max_retention_days
}

# Corporate Backup Plan
resource "aws_backup_plan" "enterprise_plan" {
  name = "${var.project_name}-plan"

  rule {
    rule_name         = "daily_backup_rule"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 2 * * ? *)" # Daily execution at 02:00 AM UTC

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }
}

# Resource Selection for Backups (Targets EBS, S3, RDS tagged with Backup = true)
resource "aws_backup_selection" "resource_selection" {
  iam_role_arn = aws_iam_role.backup_service_role.arn
  name         = "${var.project_name}-selection"
  plan_id      = aws_backup_plan.enterprise_plan.id

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }

  depends_on = [aws_backup_region_settings.settings]
}

# -------------------------------------------------------------------------
# Periodic Restore Simulation (AWS Backup Restore Testing)
# -------------------------------------------------------------------------
resource "aws_backup_restore_testing_plan" "simulation" {
  name                = "${replace(var.project_name, "-", "_")}_restore_simulation"
  schedule_expression = "cron(0 5 ? * 1 *)" # Weekly execution (Sundays at 05:00 AM UTC)

  recovery_point_selection {
    algorithm             = "LATEST_WITHIN_WINDOW"
    include_vaults        = [aws_backup_vault.main.arn]
    recovery_point_types  = ["SNAPSHOT"]
    selection_window_days = 7
  }
}

resource "aws_backup_restore_testing_selection" "ebs_simulation" {
  name                      = "${replace(var.project_name, "-", "_")}_ebs_restore_test"
  restore_testing_plan_name = aws_backup_restore_testing_plan.simulation.name
  iam_role_arn              = aws_iam_role.backup_service_role.arn
  protected_resource_type   = "AWS::EC2::Volume"
  protected_resource_arns   = ["*"]
}
