# ホスト用ロール（security-design.md §2 の app-server）。boundary を必須にし、対象を絞る。
locals {
  partition         = data.aws_partition.current.partition
  account_id        = data.aws_caller_identity.current.account_id
  bucket_arn        = "arn:${local.partition}:s3:::${var.backup_bucket_name}"
  instance_arn      = "arn:${local.partition}:ec2:${var.region}:${local.account_id}:instance/*"
  instance_profile  = "${local.account_arn}:instance-profile/${var.prefix}-app-server"
  parameter_arn     = "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter${local.param_prefix}/*"
  log_group_arns    = [for name in values(local.log_groups) : "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:${name}:*"]
  self_instance_tag = { StringEquals = { "ec2:InstanceProfile" = local.instance_profile } }
}

resource "aws_iam_role" "server" {
  name                 = "${var.prefix}-app-server"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "server" {
  name = "${var.prefix}-app-server"
  role = aws_iam_role.server.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "Backups", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${local.bucket_arn}/hourly/*", "${local.bucket_arn}/stop/*"] },
      { Sid = "DeployFiles", Effect = "Allow", Action = ["s3:GetObject"], Resource = "${local.bucket_arn}/deploy/*" },
      { Sid = "ListBackups", Effect = "Allow", Action = ["s3:ListBucket", "s3:ListBucketVersions"], Resource = local.bucket_arn },
      { Sid = "Secrets", Effect = "Allow", Action = ["ssm:GetParameter"], Resource = local.parameter_arn },
      {
        Sid       = "DecryptSecrets", Effect = "Allow", Action = ["kms:Decrypt"], Resource = "arn:${local.partition}:kms:${var.region}:${local.account_id}:key/*"
        Condition = { StringEquals = { "kms:ViaService" = "ssm.${var.region}.amazonaws.com" }, StringLike = { "kms:EncryptionContext:PARAMETER_ARN" = local.parameter_arn } }
      },
      # PutMetricData はリソース単位の制限に非対応のため、名前空間の条件で絞る。
      { Sid = "Metrics", Effect = "Allow", Action = ["cloudwatch:PutMetricData"], Resource = "*", Condition = { StringEquals = { "cloudwatch:namespace" = "Minecraft" } } },
      { Sid = "Logs", Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"], Resource = local.log_group_arns },
      # 自分のインスタンスプロファイルを持つインスタンス（= 自分自身）だけを止められる。
      { Sid = "StopSelf", Effect = "Allow", Action = ["ec2:StopInstances"], Resource = local.instance_arn, Condition = local.self_instance_tag },
      {
        Sid       = "StoppingTag", Effect = "Allow", Action = ["ec2:CreateTags", "ec2:DeleteTags"], Resource = local.instance_arn
        Condition = merge(local.self_instance_tag, { "ForAllValues:StringEquals" = { "aws:TagKeys" = ["mc:stopping"] } })
      },
      # DescribeTags はリソース単位の制限に非対応。
      { Sid = "ReadTags", Effect = "Allow", Action = ["ec2:DescribeTags"], Resource = "*" },
      { Sid = "Notify", Effect = "Allow", Action = ["sns:Publish"], Resource = var.events_topic_arn },
    ]
  })
}

resource "aws_iam_instance_profile" "server" {
  name = "${var.prefix}-app-server"
  role = aws_iam_role.server.name
}
