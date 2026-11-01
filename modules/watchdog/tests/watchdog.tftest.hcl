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
  target          = aws_lambda_function.watchdog
  override_during = plan
  values          = { arn = "arn:aws:lambda:ap-northeast-1:123456789012:function:example-watchdog" }
}

override_resource {
  target          = aws_cloudwatch_log_group.watchdog
  override_during = plan
  values          = { arn = "arn:aws:logs:ap-northeast-1:123456789012:log-group:/example/watchdog" }
}

variables {
  prefix                   = "example"
  events_topic_arn         = "arn:aws:sns:ap-northeast-1:123456789012:example-events"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/example-ci-boundary"
  source_dir               = "../../lambda/watchdog"
  build_dir                = ".build"
}

run "external_stop" {
  command = plan

  assert {
    condition     = aws_scheduler_schedule.watchdog.schedule_expression == "rate(5 minutes)"
    error_message = "watchdog は 5 分ごとに起動してください。"
  }
  assert {
    condition     = aws_iam_role.scheduler.name == "example-app-scheduler" && aws_iam_role.scheduler.permissions_boundary == "arn:aws:iam::123456789012:policy/example-ci-boundary"
    error_message = "Scheduler の実行ロールは app-scheduler とし、boundary を付けてください。"
  }
  assert {
    condition     = jsondecode(aws_iam_role.scheduler.assume_role_policy).Statement[0].Principal.Service == "scheduler.amazonaws.com"
    error_message = "Scheduler の実行ロールは scheduler.amazonaws.com だけが引き受けられるようにしてください。"
  }
  assert {
    condition = alltrue([for statement in jsondecode(aws_iam_role_policy.scheduler.policy).Statement :
    statement.Action == ["lambda:InvokeFunction"] && !contains(statement.Resource, "*")])
    error_message = "Scheduler のロールは watchdog の呼び出しだけを許可してください。"
  }
  assert {
    condition = alltrue([for statement in jsondecode(aws_iam_role_policy.watchdog.policy).Statement :
    !contains(statement.Action, "ec2:StopInstances") || statement.Condition.StringEquals["ec2:ResourceTag/mc:managed"] == "true"])
    error_message = "watchdog が止められるのは管理タグ付きのインスタンスだけにしてください。"
  }
  assert {
    condition     = aws_lambda_function.watchdog.reserved_concurrent_executions == -1
    error_message = "watchdog は予約枠を使わず、アカウントの共有同時実行枠を利用してください。"
  }
  assert {
    condition     = aws_lambda_function.watchdog.environment[0].variables["PROJECT_TAG"] == "example"
    error_message = "監視対象は Project タグで絞ってください。"
  }
}

run "reject_invalid_prefix" {
  command = plan
  variables { prefix = "X" }
  expect_failures = [var.prefix]
}

run "reject_invalid_topic" {
  command = plan
  variables { events_topic_arn = "example-events" }
  expect_failures = [var.events_topic_arn]
}
