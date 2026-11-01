data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_iam_role" "owner" {
  count = strcontains(data.aws_caller_identity.current.arn, ":assumed-role/") ? 1 : 0
  name  = split("/", data.aws_caller_identity.current.arn)[1]
}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  partition        = data.aws_partition.current.partition
  account_arn      = "arn:${local.partition}:iam::${local.account_id}"
  state_bucket_arn = "arn:${local.partition}:s3:::${var.state_bucket_name}"
  backup_arn       = "arn:${local.partition}:s3:::${var.backup_bucket_name}"
  app_role_arn     = "${local.account_arn}:role/${var.prefix}-app-*"
  ci_role_arn      = "${local.account_arn}:role/${var.prefix}-ci-*"
  ci_policy_arn    = "${local.account_arn}:policy/${var.prefix}-ci-*"
  owner_principal  = strcontains(data.aws_caller_identity.current.arn, ":assumed-role/") ? data.aws_iam_role.owner[0].arn : data.aws_caller_identity.current.arn
}

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_144:単一リージョン（東京）の方針。東京の障害時はサーバーも動かないため、state だけ複製しても復旧できない。
  #checkov:skip=CKV_AWS_145:SSE-S3 の方針。aws/s3 鍵は鍵ポリシーを編集できず、運用ロックの IAM 条件も AES256 を前提にしている。
  #checkov:skip=CKV2_AWS_62:state の変更通知は不要。デプロイの結果は workflow から SNS の events に通知する。
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "RequireTls"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }, {
      Sid       = "RestrictStatePrincipals"
      Effect    = "Deny"
      Principal = "*"
      Action    = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject", "s3:DeleteObjectVersion"]
      Resource  = ["${local.state_bucket_arn}/${var.state_key}", "${local.state_bucket_arn}/${var.state_key}.tflock"]
      Condition = { ArnNotEquals = { "aws:PrincipalArn" = [local.owner_principal, "${local.account_arn}:role/${var.prefix}-ci-plan", "${local.account_arn}:role/${var.prefix}-ci-apply"] } }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket     = aws_s3_bucket.state.id
  depends_on = [aws_s3_bucket_versioning.state]

  rule {
    id     = "prune-old-operational-lock-versions"
    status = "Enabled"
    filter { prefix = "control/" }
    noncurrent_version_expiration { noncurrent_days = 7 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.use_existing_github_oidc ? 1 : 0
  arn   = "${local.account_arn}:oidc-provider/token.actions.githubusercontent.com"

  lifecycle {
    postcondition {
      condition     = contains(self.client_id_list, "sts.amazonaws.com")
      error_message = "既存 GitHub OIDC に sts.amazonaws.com の audience が必要です。"
    }
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.use_existing_github_oidc ? 0 : 1
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  github_oidc_arn = var.use_existing_github_oidc ? data.aws_iam_openid_connect_provider.github[0].arn : aws_iam_openid_connect_provider.github[0].arn
}
