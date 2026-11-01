# 通知（LC9）。events（スクリプトとワークフロー）と alerts（アラームと予算）の 2 トピック、
# メール購読、Discord に送る notifier Lambda。メール購読は Lambda と独立しているので、Lambda が壊れても届く。
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  topics     = { events = "${var.prefix}-events", alerts = "${var.prefix}-alerts" }
  # events に Publish できるのは、ホスト・watchdog・運用と apply のワークフローだけ。
  event_publishers = [for role in ["app-server", "app-watchdog", "ci-ops", "ci-apply"] :
  "arn:${local.partition}:iam::${local.account_id}:role/${var.prefix}-${role}"]
  function_name = "${var.prefix}-notifier"
  log_group     = "/${var.prefix}/notifier"
}

resource "aws_sns_topic" "this" {
  #checkov:skip=CKV_AWS_26:本人の判断で暗号化しない。alias/aws/sns はキーポリシーを変更できず CloudWatch と Budgets から Publish できない。本文に秘匿値や識別子を含めない設計（NFR6.5）。
  for_each = local.topics
  name     = each.value
}

resource "aws_sns_topic_policy" "events" {
  arn = aws_sns_topic.this["events"].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowedPublishers"
      Effect    = "Allow"
      Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.this["events"].arn
      Condition = { ArnEquals = { "aws:PrincipalArn" = local.event_publishers } }
    }]
  })
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.this["alerts"].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AlarmsAndBudgets"
      Effect    = "Allow"
      Principal = { Service = ["cloudwatch.amazonaws.com", "budgets.amazonaws.com"] }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.this["alerts"].arn
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_sns_topic_subscription" "email" {
  # 本人がメールの確認リンクを開くと有効になる。
  for_each  = aws_sns_topic.this
  topic_arn = each.value.arn
  protocol  = "email"
  endpoint  = var.notification_email
  # events の info（起動完了・手動停止など）はメールに送らない。alerts はすべて送る。
  filter_policy       = each.key == "events" ? jsonencode({ severity = ["warn", "error"] }) : null
  filter_policy_scope = each.key == "events" ? "MessageAttributes" : null
}

resource "aws_sns_topic_subscription" "lambda" {
  for_each  = aws_sns_topic.this
  topic_arn = each.value.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.notifier.arn
}

resource "aws_lambda_permission" "sns" {
  for_each      = aws_sns_topic.this
  statement_id  = "AllowSns${title(each.key)}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = each.value.arn
}

resource "aws_cloudwatch_log_group" "notifier" {
  #checkov:skip=CKV_AWS_158:ログに秘匿値を含めない設計。KMS のカスタマーマネージドキーは予算に見合わない。
  #checkov:skip=CKV_AWS_338:Lambda のログは 14 日で十分（NFR7.15）。
  name              = local.log_group
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "notifier" {
  name                 = "${var.prefix}-app-notifier"
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

resource "aws_iam_role_policy" "notifier" {
  name = "${var.prefix}-app-notifier"
  role = aws_iam_role.notifier.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "Webhook", Effect = "Allow", Action = ["ssm:GetParameter"], Resource = local.webhook_parameter_arn },
      {
        Sid       = "DecryptWebhook", Effect = "Allow", Action = ["kms:Decrypt"], Resource = "arn:${local.partition}:kms:${var.region}:${local.account_id}:key/*"
        Condition = { StringEquals = { "kms:ViaService" = "ssm.${var.region}.amazonaws.com" }, StringLike = { "kms:EncryptionContext:PARAMETER_ARN" = local.webhook_parameter_arn } }
      },
      { Sid = "Logs", Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.notifier.arn}:*" },
    ]
  })
}

locals {
  webhook_parameter_arn = "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter${var.webhook_parameter_name}"
}

data "archive_file" "notifier" {
  type        = "zip"
  source_file = "${var.source_dir}/notifier.py"
  output_path = "${var.build_dir}/notifier.zip"
  # checkout ごとに変わるファイルの権限で zip が変わらないよう固定する（承認前後の plan 比較を安定させる）。
  output_file_mode = "0644"
}

resource "aws_lambda_function" "notifier" {
  #checkov:skip=CKV_AWS_116:失敗は CloudWatch Logs に残し、メール購読が独立した経路になる（reliability-design.md §9）。DLQ は置かない。
  #checkov:skip=CKV_AWS_117:VPC 内の資源に触れず、Discord へ直接送るため VPC に置かない。
  #checkov:skip=CKV_AWS_272:個人運用で、コードはこのリポジトリの PR と承認付き apply だけで更新される。署名基盤は置かない。
  #checkov:skip=CKV_AWS_173:環境変数は SSM のパラメータ名だけで、秘匿値は入れない。
  #checkov:skip=CKV_AWS_50:関数 1 つの単純な処理で、トレーシングは使わない（monitoring-design.md）。
  function_name                  = local.function_name
  role                           = aws_iam_role.notifier.arn
  runtime                        = "python3.13"
  architectures                  = ["arm64"]
  handler                        = "notifier.handler"
  filename                       = data.archive_file.notifier.output_path
  source_code_hash               = data.archive_file.notifier.output_base64sha256
  memory_size                    = 128
  timeout                        = 30
  reserved_concurrent_executions = 1

  environment {
    variables = { WEBHOOK_PARAMETER = var.webhook_parameter_name }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.notifier.name
  }

  depends_on = [aws_iam_role_policy.notifier]
}
