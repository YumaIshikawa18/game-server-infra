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

variables {
  prefix                   = "example"
  subnet_id                = "subnet-0123456789abcdef0"
  availability_zone        = "ap-northeast-1a"
  security_group_id        = "sg-0123456789abcdef0"
  backup_bucket_name       = "example-backup"
  events_topic_arn         = "arn:aws:sns:ap-northeast-1:123456789012:example-events"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/example-ci-boundary"
  accept_minecraft_eula    = true
  minecraft_version        = "26.3"
  compose_file             = "services:\n  mc:\n    image: itzg/minecraft-server:tag@sha256:0000000000000000000000000000000000000000000000000000000000000000\n"
}

run "secure_host" {
  command = plan

  assert {
    condition     = one(aws_instance.minecraft.metadata_options).http_tokens == "required" && one(aws_instance.minecraft.metadata_options).http_put_response_hop_limit == 2
    error_message = "IMDSv2 を必須にし、ホップ制限は 2 にしてください。"
  }
  assert {
    condition     = one(aws_instance.minecraft.root_block_device).encrypted && aws_ebs_volume.world.encrypted && aws_ebs_volume.world.type == "gp3" && aws_ebs_volume.world.size == 30
    error_message = "ルートとワールドの EBS を暗号化し、ワールドは gp3 30 GB にしてください。"
  }
  assert {
    condition     = aws_instance.minecraft.instance_type == "m7g.xlarge" && aws_instance.minecraft.tags["mc:managed"] == "true"
    error_message = "既定は m7g.xlarge、管理タグ付きにしてください。"
  }
  assert {
    condition     = aws_volume_attachment.world.stop_instance_before_detaching && aws_volume_attachment.world.device_name == "/dev/sdf"
    error_message = "ワールド EBS は停止してから外すようにしてください。"
  }
  assert {
    condition     = aws_iam_role.server.permissions_boundary == "arn:aws:iam::123456789012:policy/example-ci-boundary" && aws_iam_role.server.name == "example-app-server"
    error_message = "ホスト用ロールに permissions boundary を付けてください。"
  }
  assert {
    condition = alltrue([for statement in jsondecode(aws_iam_role_policy.server.policy).Statement :
      !contains(statement.Action, "ec2:StopInstances") || statement.Condition.StringEquals["ec2:InstanceProfile"] == "arn:aws:iam::123456789012:instance-profile/example-app-server"
    ])
    error_message = "ホストが止められるのは自分自身だけにしてください。"
  }
  assert {
    condition     = alltrue([for statement in jsondecode(aws_iam_role_policy.server.policy).Statement : statement.Resource != "*" || contains(["Metrics", "ReadTags"], statement.Sid)])
    error_message = "Resource = * はリソース制限に非対応の操作だけにしてください。"
  }
  assert {
    condition     = length(aws_ssm_document.operation) == 3 && strcontains(aws_ssm_document.operation["mc-restore-apply"].content, "allowedPattern")
    error_message = "SSM 文書 3 つを作り、引数は形式を検査してください。"
  }
  assert {
    condition = alltrue(flatten([for _, document in aws_ssm_document.operation :
      [for name in keys(jsondecode(document.content).parameters) : can(regex("^[A-Za-z0-9]+$", name))]
    ]))
    error_message = "SSM 文書のパラメータ名は英数字だけにしてください。"
  }
  assert {
    condition = (
      toset(jsondecode(aws_ssm_document.operation["mc-stop"].content).parameters.requireBackup.allowedValues) == toset(["true", "false"])
      && jsondecode(aws_ssm_document.operation["mc-stop"].content).parameters.requireBackup.default == "false"
      && strcontains(aws_ssm_document.operation["mc-stop"].content, "'{{ requireBackup }}'")
    )
    error_message = "置換前のバックアップ必須指定を停止スクリプトに渡せるようにしてください。"
  }
  assert {
    condition     = strcontains(aws_s3_object.deploy["minecraft.env"].content, "MEMORY=12G\n") && strcontains(aws_s3_object.deploy["minecraft.env"].content, "VERSION=26.3\n") && strcontains(aws_s3_object.deploy["minecraft.env"].content, "ENFORCE_WHITELIST=TRUE\n") && strcontains(aws_s3_object.deploy["minecraft.env"].content, "ONLINE_MODE=TRUE\n")
    error_message = "ヒープはメモリの 75%、バージョン固定、online-mode と whitelist の強制を設定してください。"
  }
  assert {
    condition     = !strcontains(aws_s3_object.deploy["minecraft.env"].content, "RCON_PASSWORD") && !can(regex("(?m)^WHITELIST=", aws_s3_object.deploy["minecraft.env"].content))
    error_message = "秘匿値は配布ファイルに入れず、起動時に SSM とホストで用意してください。"
  }
  assert {
    condition     = contains(keys(aws_s3_object.deploy), "bin/stop.sh") && contains(keys(aws_s3_object.deploy), "systemd/minecraft.service") && alltrue([for _, object in aws_s3_object.deploy : object.server_side_encryption == "AES256"])
    error_message = "スクリプトとユニットを暗号化して配布してください。"
  }
  assert {
    condition     = alltrue([for _, group in aws_cloudwatch_log_group.host : group.retention_in_days == 14])
    error_message = "ログの保存は 14 日にしてください。"
  }
}

run "fabric_loader" {
  command = plan
  variables {
    loader         = "fabric"
    loader_version = "0.17.3"
    mods           = [{ name = "example-mod", url = "https://example.com/mod.jar", sha256 = "0000000000000000000000000000000000000000000000000000000000000000", side = "both" }]
  }

  assert {
    condition     = strcontains(aws_s3_object.deploy["minecraft.env"].content, "TYPE=FABRIC\n") && strcontains(aws_s3_object.deploy["minecraft.env"].content, "FABRIC_LOADER_VERSION=0.17.3\n")
    error_message = "ローダーと版を設定ファイルで切り替えてください。"
  }
}

run "reject_floating_version" {
  command = plan
  variables { minecraft_version = "latest" }
  expect_failures = [var.minecraft_version]
}

run "reject_loader_without_version" {
  command = plan
  variables { loader = "neoforge" }
  expect_failures = [var.loader_version]
}

run "reject_mods_on_vanilla" {
  command = plan
  variables {
    mods = [{ name = "example-mod", url = "https://example.com/mod.jar", sha256 = "0000000000000000000000000000000000000000000000000000000000000000", side = "server" }]
  }
  expect_failures = [var.mods]
}

run "reject_architecture_mismatch" {
  command = plan
  variables { instance_type = "m7i.xlarge" }
  expect_failures = [var.instance_type]
}

run "reject_without_eula" {
  command = plan
  variables { accept_minecraft_eula = false }
  expect_failures = [var.accept_minecraft_eula]
}

run "reject_unpinned_image" {
  command = plan
  variables { compose_file = "services:\n  mc:\n    image: itzg/minecraft-server:latest\n" }
  expect_failures = [var.compose_file]
}
