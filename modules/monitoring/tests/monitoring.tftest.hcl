mock_provider "aws" {}

variables {
  prefix             = "example"
  alerts_topic_arn   = "arn:aws:sns:ap-northeast-1:123456789012:example-alerts"
  monthly_budget_usd = 20
}

run "alerts" {
  command = plan

  assert {
    condition     = toset(keys(aws_cloudwatch_metric_alarm.this)) == toset(["backup-failed", "disk-high", "backup-bucket-large"])
    error_message = "アラームは 3 つにしてください。"
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.this["backup-failed"].alarm_name == "example-backup-failed" && aws_cloudwatch_metric_alarm.this["backup-failed"].threshold == 1
    error_message = "バックアップ失敗は 1 回でアラームにしてください。"
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.this["disk-high"].evaluation_periods == 3 && aws_cloudwatch_metric_alarm.this["disk-high"].threshold == 80 && aws_cloudwatch_metric_alarm.this["disk-high"].dimensions["path"] == "/srv/minecraft"
    error_message = "ディスク使用率は 80% が 15 分続いたら警告してください。"
  }
  assert {
    condition     = alltrue([for _, alarm in aws_cloudwatch_metric_alarm.this : alarm.treat_missing_data == "notBreaching" && contains(alarm.alarm_actions, "arn:aws:sns:ap-northeast-1:123456789012:example-alerts")])
    error_message = "停止中の欠測でアラームにせず、通知は alerts に送ってください。"
  }
  assert {
    condition     = aws_budgets_budget.monthly.limit_amount == "20.00" && length(aws_budgets_budget.monthly.notification) == 4
    error_message = "予算は実績と予測の 80% / 100% で通知してください。"
  }
}

run "reject_zero_budget" {
  command = plan
  variables { monthly_budget_usd = 0 }
  expect_failures = [var.monthly_budget_usd]
}

run "reject_invalid_prefix" {
  command = plan
  variables { prefix = "Bad_Prefix" }
  expect_failures = [var.prefix]
}
