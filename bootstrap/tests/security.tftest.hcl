mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:root" }
  }
  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn            = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      client_id_list = ["sts.amazonaws.com"]
    }
  }
}

variables {
  allowed_account_ids = ["123456789012"]
  prefix              = "example"
  state_bucket_name   = "example-state"
  backup_bucket_name  = "example-backup"
  github_repository   = "example/example"
}

run "least_privilege" {
  command = plan

  assert {
    condition     = length(aws_iam_role.ci) == 3
    error_message = "CI ロールは plan / apply / ops の 3 つに分けます。"
  }
  assert {
    condition     = jsondecode(aws_iam_role.ci["plan"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "OIDC の audience を限定してください。"
  }
  assert {
    condition     = toset(jsondecode(aws_iam_role.ci["apply"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) == toset(["repo:example/example:environment:prod"])
    error_message = "apply は prod の承認を通る subject だけを許可します。"
  }
  assert {
    condition     = alltrue([for statement in jsondecode(aws_iam_role_policy.plan.policy).Statement : !contains(tolist(statement.Action), "s3:PutObject") || statement.Resource == "arn:aws:s3:::example-state/prod/terraform.tfstate.tflock"])
    error_message = "plan は state 本体を書き換えられません。"
  }
  assert {
    condition     = !strcontains(aws_iam_role_policy.ops.policy, "prod/terraform.tfstate")
    error_message = "ops に Terraform state への権限を渡さないでください。"
  }
  assert {
    condition     = alltrue([for statement in jsondecode(aws_iam_policy.apply["identity"].policy).Statement : !contains(tolist(statement.Action), "iam:CreateRole") || try(statement.Condition.StringEquals["iam:PermissionsBoundary"] == "arn:aws:iam::123456789012:policy/example-ci-boundary", false)])
    error_message = "app ロール作成時は boundary を必須にしてください。"
  }
  assert {
    condition     = alltrue([for statement in jsondecode(aws_iam_policy.apply["identity"].policy).Statement : !contains(tolist(statement.Action), "iam:PassRole") || !strcontains(jsonencode(statement.Resource), "*")]) && anytrue([for statement in jsondecode(aws_iam_policy.apply["identity"].policy).Statement : try(statement.Resource == "arn:aws:iam::123456789012:role/example-app-scheduler" && statement.Condition.StringEquals["iam:PassedToService"] == "scheduler.amazonaws.com", false)])
    error_message = "Scheduler の PassRole は専用ロールだけに限定してください。"
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.state.block_public_acls && aws_s3_bucket_public_access_block.state.block_public_policy && aws_s3_bucket_public_access_block.state.ignore_public_acls && aws_s3_bucket_public_access_block.state.restrict_public_buckets
    error_message = "state バケットの公開を禁止してください。"
  }
  assert {
    condition     = alltrue([for _, policy in aws_iam_policy.apply : length(policy.policy) <= 6144])
    error_message = "管理 IAM ポリシーがサイズ上限を超えています。"
  }
}

run "reject_short_prefix" {
  command = plan
  variables { prefix = "x" }
  expect_failures = [var.prefix]
}

run "reject_state_lock_for_operations" {
  command = plan
  variables { lock_key = "prod/terraform.tfstate.tflock" }
  expect_failures = [var.lock_key]
}
