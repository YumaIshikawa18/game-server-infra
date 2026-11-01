mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

# plan だけのテストでは ARN が未確定になるため、既知の値を与える。
override_resource {
  target          = aws_sns_topic.this
  override_during = plan
  values          = { arn = "arn:aws:sns:ap-northeast-1:123456789012:example-topic" }
}

variables {
  prefix                   = "example"
  notification_email       = "owner@example.com"
  webhook_parameter_name   = "/example/minecraft/discord-webhook"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/example-ci-boundary"
  source_dir               = "../../lambda/notifier"
  build_dir                = ".build"
}

run "routes_notifications" {
  command = plan

  assert {
    condition     = aws_sns_topic.this["events"].name == "example-events" && aws_sns_topic.this["alerts"].name == "example-alerts"
    error_message = "トピックは events と alerts に分けてください。"
  }
  assert {
    condition     = jsondecode(aws_sns_topic_subscription.email["events"].filter_policy).severity == ["warn", "error"] && aws_sns_topic_subscription.email["alerts"].filter_policy == null
    error_message = "events のメールは warn / error だけ、alerts のメールはすべて送ってください。"
  }
  assert {
    condition     = toset(jsondecode(aws_sns_topic_policy.events.policy).Statement[0].Condition.ArnEquals["aws:PrincipalArn"]) == toset([for role in ["app-server", "app-watchdog", "ci-ops", "ci-apply"] : "arn:aws:iam::123456789012:role/example-${role}"])
    error_message = "events に Publish できるロールを 4 つに限ってください。"
  }
  assert {
    condition     = jsondecode(aws_sns_topic_policy.alerts.policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "alerts への Publish は自アカウントの CloudWatch と Budgets に限ってください。"
  }
  assert {
    condition     = aws_lambda_function.notifier.runtime == "python3.13"
    error_message = "notifier は Python 3.13 にしてください。"
  }
  assert {
    condition     = contains(aws_lambda_function.notifier.architectures, "arm64")
    error_message = "notifier は arm64 にしてください。"
  }
  assert {
    condition     = aws_lambda_function.notifier.reserved_concurrent_executions == 1
    error_message = "notifier の同時実行は 1 にしてください。"
  }
  assert {
    condition     = aws_lambda_function.notifier.timeout == 30
    error_message = "notifier のタイムアウトは 30 秒にしてください。"
  }
  assert {
    condition     = aws_iam_role.notifier.permissions_boundary == "arn:aws:iam::123456789012:policy/example-ci-boundary"
    error_message = "notifier のロールに boundary を付けてください。"
  }
  assert {
    condition     = aws_cloudwatch_log_group.notifier.name == "/example/notifier"
    error_message = "ログは boundary の範囲（/<prefix>/）に置いてください。"
  }
  assert {
    condition     = aws_cloudwatch_log_group.notifier.retention_in_days == 14
    error_message = "ログは 14 日保存してください。"
  }
}

run "reject_invalid_email" {
  command = plan
  variables { notification_email = "not-an-address" }
  expect_failures = [var.notification_email]
}

run "reject_relative_parameter_name" {
  command = plan
  variables { webhook_parameter_name = "discord-webhook" }
  expect_failures = [var.webhook_parameter_name]
}
