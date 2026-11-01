# state とバックアップのサーバーアクセスログ（Q3 の B、保存 90 日）。
# ログ配信は無料で、かかるのはログの保存料金だけ。
locals {
  log_bucket_arn = "arn:${local.partition}:s3:::${var.log_bucket_name}"
  # ログを送ってよいバケットと、その書き込み先プレフィックス。
  log_sources = {
    state  = local.state_bucket_arn
    backup = local.backup_arn
  }
  log_delivery_source = "arn:${local.partition}:logs:${var.region}:${local.account_id}:*"
}

resource "aws_s3_bucket" "logs" {
  #checkov:skip=CKV_AWS_18:ログ専用バケット。自身のアクセスログを取るとログのログが循環するため取らない。
  #checkov:skip=CKV_AWS_144:単一リージョン（東京）の方針。ログは調査用で、リージョン障害時の復旧対象ではない。
  #checkov:skip=CKV_AWS_145:サーバーアクセスログの配信先は SSE-S3 のみ対応（SSE-KMS は非対応）。
  #checkov:skip=CKV2_AWS_62:ログの書き込みごとに通知する用途がない。障害通知は SNS の events / alerts に集約済み。
  bucket = var.log_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  # ACL を無効化し、配信の許可はバケットポリシーで行う。
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([{
      Sid       = "RequireTls"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [local.log_bucket_arn, "${local.log_bucket_arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }], [for name, source in local.log_sources : {
      Sid       = "S3ServerAccessLogs${title(name)}"
      Effect    = "Allow"
      Principal = { Service = "logging.s3.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${local.log_bucket_arn}/${name}/*"
      Condition = {
        ArnLike      = { "aws:SourceArn" = source }
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
      }], [{
      # VPC フローログ（envs/prod の network モジュール）。自アカウントのログ配信だけを flow/ に許可する。
      Sid       = "VpcFlowLogsWrite"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${local.log_bucket_arn}/flow/AWSLogs/${local.account_id}/*"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id, "s3:x-amz-acl" = "bucket-owner-full-control" }
        ArnLike      = { "aws:SourceArn" = local.log_delivery_source }
      }
      }, {
      Sid       = "VpcFlowLogsAclCheck"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
      Resource  = local.log_bucket_arn
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = local.log_delivery_source }
      }
    }])
  })

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket     = aws_s3_bucket.logs.id
  depends_on = [aws_s3_bucket_versioning.logs]

  rule {
    id     = "expire-access-logs"
    status = "Enabled"
    filter {}
    expiration { days = var.access_log_retention_days }
    noncurrent_version_expiration { noncurrent_days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_logging" "state" {
  bucket        = aws_s3_bucket.state.id
  target_bucket = aws_s3_bucket.logs.bucket
  target_prefix = "state/"

  depends_on = [aws_s3_bucket_policy.logs]
}
