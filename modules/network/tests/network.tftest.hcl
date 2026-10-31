mock_provider "aws" {}

variables {
  prefix            = "example"
  vpc_cidr          = "10.20.0.0/24"
  availability_zone = "ap-northeast-1a"
}

run "minecraft_network" {
  command = plan

  assert {
    condition     = aws_vpc.minecraft.cidr_block == "10.20.0.0/24"
    error_message = "専用 /24 VPC が必要です。"
  }

  assert {
    condition     = !aws_subnet.public.map_public_ip_on_launch
    error_message = "自動割り当ての公開 IP は使わず EIP を関連付けます。"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.minecraft.from_port == 25565 && aws_vpc_security_group_ingress_rule.minecraft.to_port == 25565 && aws_vpc_security_group_ingress_rule.minecraft.ip_protocol == "tcp"
    error_message = "受信は Minecraft の TCP ポートだけです。"
  }
}

run "reject_invalid_cidr" {
  command = plan

  variables {
    vpc_cidr = "10.20.0.0/16"
  }

  expect_failures = [var.vpc_cidr]
}

run "reject_other_region" {
  command = plan

  variables {
    availability_zone = "us-east-1a"
  }

  expect_failures = [var.availability_zone]
}

run "reject_invalid_prefix" {
  command = plan

  variables {
    prefix = "INVALID"
  }

  expect_failures = [var.prefix]
}
