# ゲームホスト（LC4）。ワールド EBS と EIP はインスタンスと分け、prevent_destroy で守る。
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.cpu_architecture}"
}

data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type
}

locals {
  allowed_instance_types = {
    arm64  = ["m7g.large", "m7g.xlarge", "m7g.2xlarge", "m8g.large", "m8g.xlarge", "m8g.2xlarge", "r7g.large", "r7g.xlarge"]
    x86_64 = ["m7i.large", "m7i.xlarge", "m7i.2xlarge", "m7a.large", "m7a.xlarge", "r7i.large", "r7i.xlarge"]
  }
  # 既定はインスタンスメモリの 75%（16 GiB なら 12G）。
  heap_gb      = coalesce(var.jvm_heap_override, floor(data.aws_ec2_instance_type.selected.memory_size * 0.75 / 1024))
  compose_arch = var.cpu_architecture == "arm64" ? "aarch64" : "x86_64"
  account_arn  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}"
  param_prefix = "/${var.prefix}/minecraft"
  log_groups = {
    server  = "/${var.prefix}/server"
    scripts = "/${var.prefix}/scripts"
  }
}

resource "aws_cloudwatch_log_group" "host" {
  #checkov:skip=CKV_AWS_158:ログ本文に秘匿値を含めない設計。KMS のカスタマーマネージドキーは予算に見合わない。
  #checkov:skip=CKV_AWS_338:プレイヤー名を含むため、保存は 14 日に短くする（NFR7.16）。
  for_each          = local.log_groups
  name              = each.value
  retention_in_days = var.log_retention_days
}

# EIP は起動前から使えるよう、先に作った ENI に関連付けてから主 ENI として起動する。
resource "aws_network_interface" "minecraft" {
  subnet_id       = var.subnet_id
  security_groups = [var.security_group_id]
  description     = "Minecraft primary interface"

  tags = {
    Name = "${var.prefix}-minecraft"
  }
}

resource "aws_eip" "minecraft" {
  #checkov:skip=CKV2_AWS_19:EIP はインスタンスの主 ENI（aws_network_interface.minecraft）に関連付けている。Checkov は ENI 経由の関連付けを認識しない。
  domain = "vpc"

  tags = {
    Name = "${var.prefix}-minecraft"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_eip_association" "minecraft" {
  allocation_id        = aws_eip.minecraft.id
  network_interface_id = aws_network_interface.minecraft.id
}

resource "aws_ebs_volume" "world" {
  #checkov:skip=CKV_AWS_189:AWS 管理キー（aws/ebs）で暗号化する。カスタマーマネージドキーは月約 150 円で、SNS と同じく予算に見合わないと本人が判断済み。
  availability_zone = var.availability_zone
  size              = var.world_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${var.prefix}-world"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_instance" "minecraft" {
  #checkov:skip=CKV_AWS_126:1 分間隔の詳細モニタリングは不要。死活は health.sh の独自メトリクスで見る。
  ami                     = data.aws_ssm_parameter.ami.insecure_value
  instance_type           = var.instance_type
  iam_instance_profile    = aws_iam_instance_profile.server.name
  ebs_optimized           = true
  disable_api_termination = false
  user_data_base64 = base64gzip(templatefile("${path.module}/user_data.sh.tftpl", {
    region         = var.region
    bucket         = var.backup_bucket_name
    volume_id      = aws_ebs_volume.world.id
    compose_url    = "https://github.com/docker/compose/releases/download/${var.docker_compose_plugin.version}/docker-compose-linux-${local.compose_arch}"
    compose_sha256 = var.docker_compose_plugin.sha256[var.cpu_architecture]
  }))

  primary_network_interface {
    network_interface_id = aws_network_interface.minecraft.id
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name         = "${var.prefix}-minecraft"
    "mc:managed" = "true"
  }

  lifecycle {
    # AMI の更新で意図せず置き換えない。置き換えは deploy.yml の保護付きで明示的に行う。
    # mc:stopping と mc:mode はスクリプトと workflow が実行時に付け外しするので、差分にしない。
    ignore_changes = [ami, tags["mc:stopping"], tags["mc:mode"]]

    precondition {
      condition     = contains(data.aws_ec2_instance_type.selected.supported_architectures, var.cpu_architecture)
      error_message = "instance_type が cpu_architecture に対応していません。"
    }
    precondition {
      condition     = local.heap_gb >= 2 && local.heap_gb * 1024 <= data.aws_ec2_instance_type.selected.memory_size - 1024
      error_message = "JVM ヒープは 2 GB 以上、インスタンスメモリより 1 GB 以上小さくしてください。"
    }
  }

  # 起動時の user data が配布ファイルとログ出力先を前提にする。
  depends_on = [aws_eip_association.minecraft, aws_s3_object.deploy, aws_cloudwatch_log_group.host]
}

resource "aws_volume_attachment" "world" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.world.id
  instance_id = aws_instance.minecraft.id
  # 外す前にインスタンスを止め、書き込み中のデタッチを防ぐ。
  stop_instance_before_detaching = true
}
