mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_ec2_instance_type" {
    defaults = { memory_size = 16384, supported_architectures = ["arm64"] }
  }
}

# モジュール間で受け渡す ARN は、plan だけのテストでは未確定になるため既知の値を与える。
override_module {
  target          = module.notifier
  override_during = plan
  outputs = {
    events_topic_arn = "arn:aws:sns:ap-northeast-1:123456789012:example-events"
    alerts_topic_arn = "arn:aws:sns:ap-northeast-1:123456789012:example-alerts"
  }
}

variables {
  allowed_account_ids   = ["123456789012"]
  prefix                = "example"
  backup_bucket_name    = "example-backup"
  log_bucket_name       = "example-logs"
  notification_email    = "owner@example.com"
  monthly_budget_usd    = 20
  accept_minecraft_eula = true
}

run "production_wiring" {
  command = plan

  assert {
    condition     = module.minecraft_server.parameter_prefix == "/example/minecraft"
    error_message = "whitelist は /<prefix>/minecraft/ の下に置いてください（boundary の範囲）。"
  }
  assert {
    condition     = output.discord_webhook_parameter == "/example/minecraft/discord-webhook"
    error_message = "Webhook のパラメータも /<prefix>/ の下に置いてください。"
  }
  assert {
    condition     = local.permissions_boundary_arn == "arn:aws:iam::123456789012:policy/example-ci-boundary"
    error_message = "bootstrap の permissions boundary を使ってください。"
  }
  assert {
    condition     = local.minecraft.version == "26.3" && local.minecraft.loader == "vanilla"
    error_message = "初回は 26.3 の vanilla で接続を確認します（Q4）。"
  }
}

run "reject_other_region" {
  command = plan
  variables { region = "us-east-1" }
  expect_failures = [var.region]
}

run "reject_invalid_prefix" {
  command = plan
  variables { prefix = "Example" }
  expect_failures = [var.prefix]
}
