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
  allowed_account_ids        = ["123456789012"]
  prefix                     = "example"
  state_bucket_name          = "example-state"
  backup_bucket_name         = "example-backup"
  log_bucket_name            = "example-logs"
  github_repository          = "example/example"
  github_oidc_subject_prefix = "repo:example@100/example@200"
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
    condition     = toset(jsondecode(aws_iam_role.ci["apply"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) == toset(["repo:example@100/example@200:environment:prod"])
    error_message = "apply は prod の承認を通る subject だけを許可します。"
  }
  assert {
    condition     = toset(jsondecode(aws_iam_role.ci["plan"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) == toset(["repo:example@100/example@200:pull_request", "repo:example@100/example@200:ref:refs/heads/master"])
    error_message = "plan は同一リポジトリの PR と master だけを許可します。"
  }
  assert {
    condition     = toset(jsondecode(aws_iam_role.ci["ops"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) == toset(["repo:example@100/example@200:environment:ops"])
    error_message = "ops は ops Environment の subject だけを許可します。"
  }
  assert {
    condition     = alltrue([for _, role in aws_iam_role.ci : !strcontains(role.assume_role_policy, "*") && role.max_session_duration == 3600])
    error_message = "trust policy にワイルドカードを使わず、セッションは 1 時間までにしてください。"
  }
  assert {
    condition     = alltrue([for statement in jsondecode(aws_iam_policy.boundary.policy).Statement : statement.Resource != "*" || alltrue([for action in tolist(statement.Action) : !startswith(action, "ssm:") || action == "ssm:DescribeInstanceInformation"])])
    error_message = "boundary の ssm 操作は対象リソースを限定してください。"
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
    condition     = anytrue([for statement in jsondecode(aws_iam_policy.apply["reads"].policy).Statement : contains(tolist(statement.Action), "ssm:GetParameter") && contains(tolist(statement.Resource), "arn:aws:ssm:ap-northeast-1::parameter/aws/service/ami-amazon-linux-latest/*")])
    error_message = "apply ロールにも、作り直す plan で使う読み取り（AMI の SSM パラメータなど）を付けてください。"
  }
  assert {
    condition     = toset(keys(aws_iam_role_policy_attachment.apply)) == toset(keys(aws_iam_policy.apply))
    error_message = "apply 用のポリシーはすべて apply ロールに付けてください。"
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.apply) <= 10
    error_message = "ロールに付けられる管理ポリシーは 10 個までです。"
  }
  assert {
    condition     = alltrue([for _, policy in aws_iam_policy.apply : length(policy.policy) <= 6144])
    error_message = "管理 IAM ポリシーがサイズ上限を超えています。"
  }
}

run "deployment_creation_permissions" {
  command = plan

  assert {
    condition = alltrue([for action in ["ec2:CreateSubnet", "ec2:CreateRouteTable", "ec2:CreateSecurityGroup", "ec2:CreateFlowLogs"] :
      anytrue([for statement in jsondecode(aws_iam_policy.apply["compute"].policy).Statement :
        contains(tolist(statement.Action), action)
        && try(statement.Resource == "arn:aws:ec2:ap-northeast-1:123456789012:vpc/*", false)
        && try(statement.Condition.StringEquals["ec2:ResourceTag/Project"] == "example", false)
      ])
    ])
    error_message = "VPC 配下の作成には、同じ Project の親 VPC の認可も必要です。"
  }
  assert {
    condition = anytrue([for statement in jsondecode(aws_iam_policy.apply["compute"].policy).Statement :
      contains(tolist(statement.Action), "ec2:CreateNetworkInterface")
      && try(toset(statement.Resource) == toset(["arn:aws:ec2:ap-northeast-1:123456789012:subnet/*", "arn:aws:ec2:ap-northeast-1:123456789012:security-group/*"]), false)
      && try(statement.Condition.StringEquals["ec2:ResourceTag/Project"] == "example", false)
    ])
    error_message = "ENI 作成の親 subnet と SG は同じ Project に限定してください。"
  }
  assert {
    condition = alltrue([for statement in jsondecode(aws_iam_policy.apply["compute"].policy).Statement :
      length(setintersection(toset(statement.Action), toset(local.ec2_create_actions))) == 0
      || try(statement.Condition.StringEquals["aws:RequestTag/Project"] == "example", false)
      || try(statement.Condition.StringEquals["ec2:ResourceTag/Project"] == "example", false)
    ])
    error_message = "EC2 の作成は新規または既存リソースの Project 条件を必須にしてください。"
  }
  assert {
    condition = anytrue([for statement in jsondecode(aws_iam_policy.apply["storage"].policy).Statement :
      contains(tolist(statement.Action), "s3:TagResource")
      && try(statement.Resource == "arn:aws:s3:::example-backup", false)
    ])
    error_message = "タグ付きバケット作成の TagResource はバックアップバケットだけに許可してください。"
  }
  assert {
    condition = alltrue([for policy in [aws_iam_role_policy.plan.policy, aws_iam_policy.apply["reads"].policy, aws_iam_policy.apply["services"].policy] :
      anytrue([for statement in jsondecode(policy).Statement :
        contains(tolist(statement.Action), "sns:GetSubscriptionAttributes")
        && try(statement.Resource == "arn:aws:sns:ap-northeast-1:123456789012:example-*", false)
      ])
      ]) && alltrue([for statement in jsondecode(aws_iam_policy.apply["services"].policy).Statement :
      length(setintersection(toset(statement.Action), toset(["sns:SetSubscriptionAttributes", "sns:Unsubscribe"]))) == 0
      || try(statement.Resource == "arn:aws:sns:ap-northeast-1:123456789012:example-*", false)
    ])
    error_message = "SNS の購読操作の IAM Resource は購読 ARN ではなく対象 topic ARN にしてください。"
  }
}

run "operational_lock_permissions" {
  command = plan

  assert {
    condition = alltrue([for policy in [aws_iam_role_policy.ops.policy, aws_iam_policy.apply["state"].policy] :
      anytrue([for statement in jsondecode(policy).Statement :
        statement.Effect == "Allow" && contains(tolist(statement.Action), "s3:GetObject")
        && try(statement.Resource == "arn:aws:s3:::example-state/control/operation.lock", false)
        && !can(statement.Condition)
      ])
    ])
    error_message = "apply と ops の条件付きロック解除には、専用ロック 1 キーの GetObject が必要です。"
  }
  assert {
    condition = alltrue([for statement in jsondecode(aws_iam_role_policy.ops.policy).Statement :
      !contains(tolist(statement.Action), "s3:GetObject")
      || try(statement.Resource == "arn:aws:s3:::example-state/control/operation.lock", false)
    ])
    error_message = "ops の読み取りを state 本体やロック以外のキーに広げないでください。"
  }
  assert {
    condition = alltrue([for policy in [aws_iam_role_policy.ops.policy, aws_iam_policy.apply["state"].policy] :
      anytrue([for statement in jsondecode(policy).Statement :
        contains(tolist(statement.Action), "s3:DeleteObject")
        && try(statement.Resource == "arn:aws:s3:::example-state/control/operation.lock", false)
        && try(statement.Condition.Null["s3:if-match"] == "false", false)
      ])
    ])
    error_message = "専用ロックの削除は If-Match の条件を維持してください。"
  }
}

run "access_logs" {
  command = plan

  assert {
    condition     = aws_s3_bucket_logging.state.target_bucket == "example-logs" && aws_s3_bucket_logging.state.target_prefix == "state/"
    error_message = "state バケットのアクセスログをログバケットの state/ に送ってください。"
  }
  assert {
    condition     = one([for rule in aws_s3_bucket_lifecycle_configuration.logs.rule : rule.expiration[0].days]) == 90
    error_message = "アクセスログの保存期間は 90 日にしてください。"
  }
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.logs.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" && aws_s3_bucket_public_access_block.logs.restrict_public_buckets
    error_message = "ログバケットは SSE-S3 で暗号化し、公開を禁止してください。"
  }
  assert {
    condition = alltrue([for statement in jsondecode(aws_s3_bucket_policy.logs.policy).Statement : statement.Effect == "Deny" || statement.Principal.Service == "delivery.logs.amazonaws.com" || (
      statement.Principal.Service == "logging.s3.amazonaws.com" && statement.Action == "s3:PutObject"
      && statement.Condition.StringEquals["aws:SourceAccount"] == "123456789012"
      && contains(["arn:aws:s3:::example-state", "arn:aws:s3:::example-backup"], statement.Condition.ArnLike["aws:SourceArn"])
    )])
    error_message = "ログの書き込みは S3 のログ配信サービスから、state とバックアップの分だけに限定してください。"
  }
}

run "flow_log_delivery" {
  command = plan

  assert {
    condition = alltrue([for statement in jsondecode(aws_s3_bucket_policy.logs.policy).Statement : statement.Principal == "*" || statement.Principal.Service != "delivery.logs.amazonaws.com" || (
      statement.Condition.StringEquals["aws:SourceAccount"] == "123456789012" && statement.Condition.ArnLike["aws:SourceArn"] == "arn:aws:logs:ap-northeast-1:123456789012:*"
    )])
    error_message = "フローログの配信は自アカウントのログ配信だけに許可してください。"
  }
  assert {
    condition     = anytrue([for statement in jsondecode(aws_s3_bucket_policy.logs.policy).Statement : try(statement.Resource == "arn:aws:s3:::example-logs/flow/AWSLogs/123456789012/*", false)])
    error_message = "フローログの書き込みは flow/ に限ってください。"
  }
}

run "reject_long_log_retention" {
  command = plan
  variables { access_log_retention_days = 400 }
  expect_failures = [var.access_log_retention_days]
}

run "legacy_subject_format" {
  command = plan
  variables { github_oidc_subject_prefix = "repo:example/example" }

  assert {
    condition     = toset(jsondecode(aws_iam_role.ci["apply"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) == toset(["repo:example/example:environment:prod"])
    error_message = "ID なしの従来形式の sub も使えるようにしてください。"
  }
}

run "reject_subject_for_other_repository" {
  command = plan
  variables { github_oidc_subject_prefix = "repo:example@100/other@200" }
  expect_failures = [var.github_oidc_subject_prefix]
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
