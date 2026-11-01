# ホストの外からの強制停止（LC8）。EventBridge Scheduler が 5 分ごとに Lambda を呼ぶ。
# Scheduler の実行ロールは watchdog の呼び出しだけを許可する（environment-provisioning の Q2）。
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition     = data.aws_partition.current.partition
  account_id    = data.aws_caller_identity.current.account_id
  function_name = "${var.prefix}-watchdog"
  instance_arn  = "arn:${local.partition}:ec2:${var.region}:${local.account_id}:instance/*"
}

resource "aws_cloudwatch_log_group" "watchdog" {
  #checkov:skip=CKV_AWS_158:ログに秘匿値を含めない設計。KMS のカスタマーマネージドキーは予算に見合わない。
  #checkov:skip=CKV_AWS_338:Lambda のログは 14 日で十分（NFR7.15）。
  name              = "/${var.prefix}/watchdog"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "watchdog" {
  name                 = "${var.prefix}-app-watchdog"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "watchdog" {
  name = "${var.prefix}-app-watchdog"
  role = aws_iam_role.watchdog.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Describe と GetMetricData はリソース単位の制限に非対応。
      { Sid = "Read", Effect = "Allow", Action = ["ec2:DescribeInstances", "cloudwatch:GetMetricData"], Resource = "*" },
      {
        Sid       = "StopManaged", Effect = "Allow", Action = ["ec2:StopInstances"], Resource = local.instance_arn
        Condition = { StringEquals = { "ec2:ResourceTag/Project" = var.prefix, "ec2:ResourceTag/mc:managed" = "true" } }
      },
      { Sid = "Notify", Effect = "Allow", Action = ["sns:Publish"], Resource = var.events_topic_arn },
      { Sid = "Logs", Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.watchdog.arn}:*" },
    ]
  })
}

data "archive_file" "watchdog" {
  type        = "zip"
  source_file = "${var.source_dir}/watchdog.py"
  output_path = "${var.build_dir}/watchdog.zip"
  # checkout ごとに変わるファイルの権限で zip が変わらないよう固定する（承認前後の plan 比較を安定させる）。
  output_file_mode = "0644"
}

resource "aws_lambda_function" "watchdog" {
  #checkov:skip=CKV_AWS_115:本人の選択（deployment-execution Q12）で予約枠を使わずアカウントの共有枠を利用する。5 分間隔・最大 30 秒で実行し、対象は管理タグ付き EC2 だけに限定する。
  #checkov:skip=CKV_AWS_116:5 分ごとに起動し直すため、失敗した回は次の回が補う。DLQ は置かない。
  #checkov:skip=CKV_AWS_117:AWS API だけを呼ぶため VPC に置かない（NAT なしの構成）。
  #checkov:skip=CKV_AWS_272:個人運用で、コードはこのリポジトリの PR と承認付き apply だけで更新される。署名基盤は置かない。
  #checkov:skip=CKV_AWS_173:環境変数はタグの値とトピック ARN だけで、秘匿値は入れない。
  #checkov:skip=CKV_AWS_50:関数 1 つの単純な処理で、トレーシングは使わない（monitoring-design.md）。
  function_name                  = local.function_name
  role                           = aws_iam_role.watchdog.arn
  runtime                        = "python3.13"
  architectures                  = ["arm64"]
  handler                        = "watchdog.handler"
  filename                       = data.archive_file.watchdog.output_path
  source_code_hash               = data.archive_file.watchdog.output_base64sha256
  memory_size                    = 128
  timeout                        = 30
  reserved_concurrent_executions = -1

  environment {
    variables = {
      PROJECT_TAG      = var.prefix
      EVENTS_TOPIC_ARN = var.events_topic_arn
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.watchdog.name
  }

  depends_on = [aws_iam_role_policy.watchdog]
}

resource "aws_iam_role" "scheduler" {
  name                 = "${var.prefix}-app-scheduler"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.prefix}-app-scheduler"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeWatchdogOnly"
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = [aws_lambda_function.watchdog.arn, "${aws_lambda_function.watchdog.arn}:*"]
    }]
  })
}

resource "aws_scheduler_schedule" "watchdog" {
  #checkov:skip=CKV_AWS_297:スケジュールの入力は空の JSON だけで、秘匿値を含まない。KMS のカスタマーマネージドキーは予算に見合わない。
  name                         = "${var.prefix}-watchdog"
  schedule_expression          = "rate(5 minutes)"
  schedule_expression_timezone = "Asia/Tokyo"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.watchdog.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = "{}"

    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 300
    }
  }
}
