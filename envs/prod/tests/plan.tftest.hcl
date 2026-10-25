# AWS に接続せずに、変数による分岐と precondition を plan で検証する
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }

  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }

  mock_data "aws_region" {
    defaults = { region = "ap-northeast-1" }
  }

  mock_data "aws_ec2_instance_type_offerings" {
    defaults = { locations = ["ap-northeast-1c", "ap-northeast-1a"] }
  }

  mock_data "aws_ec2_instance_type" {
    defaults = { supported_architectures = ["arm64"], memory_size = 2048 }
  }

  mock_data "aws_ip_ranges" {
    defaults = { cidr_blocks = ["3.112.23.0/29"] }
  }

  mock_data "aws_subnet" {
    defaults = { id = "subnet-12345678", availability_zone = "ap-northeast-1a" }
  }

  mock_data "aws_vpc" {
    defaults = { id = "vpc-12345678" }
  }

  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-0123456789abcdef0" }
  }

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }

  mock_resource "aws_ebs_volume" {
    defaults = { id = "vol-0123456789abcdef0" }
  }

  mock_resource "aws_ssm_parameter" {
    defaults = { arn = "arn:aws:ssm:ap-northeast-1:123456789012:parameter/mc/ram" }
  }
}

run "defaults" {
  # mock provider 上の apply なので AWS には接続しない
  command = apply

  assert {
    condition     = output.availability_zone == "ap-northeast-1a"
    error_message = "提供されている AZ のうち、辞書順で最初の AZ が選ばれるはずです。"
  }

  assert {
    condition     = length(module.network.subnet_id) > 0 && length(module.world_backup) == 0
    error_message = "既定では専用 VPC を作り、バックアップは作らないはずです。"
  }

  assert {
    condition     = module.minecraft_server.server_address != null
    error_message = "接続先が出力されるはずです。"
  }
}

run "default_vpc_backup_no_ssh" {
  # mock provider 上の apply なので AWS には接続しない
  command = apply

  variables {
    use_default_vpc = true
    enable_backup   = true
    enable_ssh      = false
    accept_eula     = true
  }

  assert {
    condition     = module.network.vpc_id == "vpc-12345678"
    error_message = "use_default_vpc = true なら既定 VPC を使うはずです。"
  }

  assert {
    condition     = length(module.world_backup) == 1
    error_message = "enable_backup = true ならバックアップモジュールが作られるはずです。"
  }
}

run "custom_instance_connect_cidrs" {
  # mock provider 上の apply なので AWS には接続しない
  command = apply

  variables {
    instance_connect_cidrs = ["192.0.2.0/29"]
  }
}

run "too_short_shutdown_timer" {
  command = plan

  variables {
    shutdown_timer_seconds = 60
  }

  expect_failures = [var.shutdown_timer_seconds]
}
