# SNS Topic for Backup Operational Alerts
resource "aws_sns_topic" "backup_alerts" {
  name = "${var.project_name}-alerts-topic"
}

# SNS Topic Subscription for Email Notifications
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.backup_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Amazon EventBridge Rule to capture AWS Backup Job State Changes
resource "aws_cloudwatch_event_rule" "backup_events" {
  name        = "${var.project_name}-backup-events-rule"
  description = "Capture AWS Backup state changes and job failures"

  event_pattern = jsonencode({
    source = ["aws.backup"]
    detail-type = [
      "Backup Job State Change",
      "Restore Job State Change"
    ]
    detail = {
      state = [
        "COMPLETED",
        "FAILED",
        "ABORTED"
      ]
    }
  })
}

# EventBridge Target to route events to the SNS Topic
resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.backup_events.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.backup_alerts.arn
}

# Resource Policy for SNS Topic to allow EventBridge publishing
resource "aws_sns_topic_policy" "default" {
  arn = aws_sns_topic.backup_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.backup_alerts.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.backup_events.arn
          }
        }
      }
    ]
  })
}
