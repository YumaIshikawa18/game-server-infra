# JVM ヒープがインスタンスのメモリを超える設定を plan で弾けることを確認する
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "ap-northeast-1" }
  }

  mock_data "aws_subnet" {
    defaults = { availability_zone = "ap-northeast-1a" }
  }

  mock_data "aws_ec2_instance_type" {
    defaults = { supported_architectures = ["arm64"], memory_size = 2048 }
  }

  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-0123456789abcdef0" }
  }

  mock_resource "aws_ebs_volume" {
    defaults = { id = "vol-0123456789abcdef0" }
  }
}

variables {
  name_prefix                   = "minecraft-test"
  instance_type                 = "t4g.small"
  subnet_id                     = "subnet-12345678"
  security_group_ids            = ["sg-12345678"]
  instance_profile_name         = "minecraft-test-server"
  minecraft_version             = "26.3"
  ram_parameter_name            = "/mc/ram"
  shutdown_timer_parameter_name = "/mc/shutdowntimer"
  shutdown_timer_seconds        = 900
}

run "heap_fits" {
  # mock provider 上の apply なので AWS には接続しない
  command = apply

  variables {
    jvm_memory_mb = 1300
  }

  assert {
    condition     = strcontains(aws_instance.this.user_data, "eula=$EULA_VALUE") && strcontains(aws_instance.this.user_data, "ACCEPT_EULA=\"false\"")
    error_message = "accept_eula の既定値 false が user data に渡るはずです。"
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 が必須になっているはずです。"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted && aws_ebs_volume.data.encrypted
    error_message = "EBS は暗号化されているはずです。"
  }
}

run "heap_exceeds_memory" {
  command = plan

  variables {
    jvm_memory_mb = 1800
  }

  expect_failures = [aws_instance.this]
}
