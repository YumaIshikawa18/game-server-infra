# 監視（LC10、monitoring-design.md の Alerts）。アラームと予算の通知は alerts トピックへ送る。
# アラーム名は "<prefix>-<種類>"。notifier は種類から severity を決める。
locals {
  alarms = {
    backup-failed = {
      description = "Hourly or stop backup failed. Runbook: backup-failed."
      metric      = "BackupFailures"
      statistic   = "Sum"
      period      = 300
      evaluations = 1
      threshold   = 1
      dimensions  = {}
    }
    disk-high = {
      description = "World volume is 80 percent full. Runbook: disk-high."
      metric      = "disk_used_percent"
      statistic   = "Maximum"
      period      = 300
      evaluations = 3
      threshold   = 80
      # CloudWatch Agent の設定（omit_hostname, drop_device）と同じディメンション。
      dimensions = { path = "/srv/minecraft", fstype = "xfs" }
    }
    backup-bucket-large = {
      description = "Backup bucket exceeds 80 GiB. Runbook: backup-bucket-large."
      metric      = "BackupBucketBytes"
      statistic   = "Maximum"
      period      = 3600
      evaluations = 1
      threshold   = 80 * 1024 * 1024 * 1024
      dimensions  = {}
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each            = local.alarms
  alarm_name          = "${var.prefix}-${each.key}"
  alarm_description   = each.value.description
  namespace           = "Minecraft"
  metric_name         = each.value.metric
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluations
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  dimensions          = each.value.dimensions
  # 停止中はメトリクスが届かないので、欠測は正常として扱う。
  treat_missing_data = "notBreaching"
  alarm_actions      = [var.alerts_topic_arn]
  ok_actions         = [var.alerts_topic_arn]
}

# Lambda 自体の失敗を検知する。notifier が失敗しても、alerts トピックのメール購読には直接届く。
# 関数名は notifier / watchdog モジュールの "<prefix>-<名前>" と合わせる。
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each            = toset(["notifier", "watchdog"])
  alarm_name          = "${var.prefix}-${each.key}-errors"
  alarm_description   = "Lambda ${each.key} failed. Check its CloudWatch Logs."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  dimensions          = { FunctionName = "${var.prefix}-${each.key}" }
  # 実行がない間はメトリクスが届かないので、欠測は正常として扱う。
  treat_missing_data = "notBreaching"
  alarm_actions      = [var.alerts_topic_arn]
  ok_actions         = [var.alerts_topic_arn]
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.prefix}-monthly"
  budget_type  = "COST"
  limit_amount = format("%.2f", var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = { for pair in setproduct(["ACTUAL", "FORECASTED"], [80, 100]) : "${pair[0]}-${pair[1]}" => pair }
    content {
      notification_type         = notification.value[0]
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value[1]
      threshold_type            = "PERCENTAGE"
      subscriber_sns_topic_arns = [var.alerts_topic_arn]
    }
  }
}
