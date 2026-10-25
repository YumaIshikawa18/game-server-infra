data "aws_region" "current" {}

data "aws_subnet" "this" {
  id = var.subnet_id
}

data "aws_ec2_instance_type" "this" {
  instance_type = var.instance_type
}

locals {
  architecture = contains(data.aws_ec2_instance_type.this.supported_architectures, "arm64") ? "arm64" : "x86_64"

  # データ用 EBS は Nitro では NVMe として見え、/dev/disk/by-id にボリューム ID（ハイフンなし）で現れる
  data_volume_device_name = "nvme-Amazon_Elastic_Block_Store_${replace(aws_ebs_volume.data.id, "-", "")}"

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    aws_region                    = data.aws_region.current.region
    minecraft_version             = var.minecraft_version
    accept_eula                   = var.accept_eula
    minecraft_port                = var.minecraft_port
    data_volume_device_name       = local.data_volume_device_name
    ram_parameter_name            = var.ram_parameter_name
    default_ram_mb                = var.jvm_memory_mb
    shutdown_timer_parameter_name = var.shutdown_timer_parameter_name
    ops_parameter_name            = var.ops_parameter_name
    whitelist_parameter_name      = var.whitelist_parameter_name
    secure_parameter_dummy_value  = var.secure_parameter_dummy_value
    default_shutdown_timer        = var.shutdown_timer_seconds
    backup_s3_uri                 = var.backup_s3_uri == null ? "" : var.backup_s3_uri
    backup_on_calendar            = var.backup_on_calendar
  })

  public_ip = var.use_eip ? aws_eip.this[0].public_ip : aws_instance.this.public_ip
}

# Amazon Linux 2023 の最新 AMI（AWS 公開の SSM パラメータ）
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${local.architecture}"
}

################################################################################
# EC2
################################################################################

#trivy:ignore:AWS-0027 EBS は AWS 管理キー（aws/ebs）で暗号化する。CMK は月額費用がかかるため使わない
resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.al2023_ami.insecure_value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name

  # EIP を使う場合も、関連付けまでの間に user data がインターネットへ出られるよう付けておく
  # （EIP を関連付けると自動割り当ての IP は解放される）
  associate_public_ip_address = true

  # 監視スクリプトの `systemctl poweroff` を EC2 の停止として扱う（終了ではない）
  instance_initiated_shutdown_behavior = "stop"

  user_data                   = local.user_data
  user_data_replace_on_change = true

  # T 系のみ有効。unlimited は CPU クレジット超過分が課金される
  dynamic "credit_specification" {
    for_each = startswith(var.instance_type, "t") ? [1] : []
    content {
      cpu_credits = var.cpu_credits
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${var.name_prefix}-server" }

  lifecycle {
    # AMI の更新だけでインスタンスが作り直されないようにする。
    # 更新したい場合は `terraform apply -replace=module.minecraft_server.aws_instance.this` を使う
    ignore_changes = [ami]

    precondition {
      condition     = var.jvm_memory_mb + var.os_reserved_memory_mb <= data.aws_ec2_instance_type.this.memory_size
      error_message = "jvm_memory_mb (${var.jvm_memory_mb} MB) + OS 用 ${var.os_reserved_memory_mb} MB が ${var.instance_type} のメモリ (${data.aws_ec2_instance_type.this.memory_size} MiB) を超えています。"
    }
  }
}

################################################################################
# ワールド用 EBS（インスタンスの作り直しでも残る）
################################################################################

#trivy:ignore:AWS-0027 EBS は AWS 管理キー（aws/ebs）で暗号化する。CMK は月額費用がかかるため使わない
resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.this.availability_zone
  type              = "gp3"
  size              = var.data_volume_size
  encrypted         = true
  final_snapshot    = var.data_volume_final_snapshot

  tags = { Name = "${var.name_prefix}-world" }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.this.id

  # 置き換え時はインスタンスを停止（= minecraft.service の ExecStop で保存）してから外す
  stop_instance_before_detaching = true
}

################################################################################
# Elastic IP
################################################################################

resource "aws_eip" "this" {
  count = var.use_eip ? 1 : 0

  domain = "vpc"

  tags = { Name = "${var.name_prefix}-server" }
}

resource "aws_eip_association" "this" {
  count = var.use_eip ? 1 : 0

  allocation_id = aws_eip.this[0].id
  instance_id   = aws_instance.this.id
}

################################################################################
# server-control ワークフローの status 用 SSM ドキュメント
# AWS-RunShellScript を許可すると任意コマンドを実行できてしまうため、固定の読み取り専用スクリプトに限定する
################################################################################

resource "aws_ssm_document" "status" {
  name            = "${var.name_prefix}-server-status"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Show Minecraft server status"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "status"
      inputs = {
        timeoutSeconds = "60"
        runCommand     = [templatefile("${path.module}/templates/status.sh.tftpl", { minecraft_port = var.minecraft_port })]
      }
    }]
  })
}
