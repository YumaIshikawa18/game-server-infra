# ワールドのバックアップ（hourly/・stop/）とホストへの配布ファイル（deploy/）の保管庫（LC6）。
# 世代の削除はホスト上のスクリプトが行い、ここでは旧版と未完了アップロードだけを掃除する。
locals {
  bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${var.bucket_name}"
}

data "aws_partition" "current" {}

resource "aws_s3_bucket" "backup" {
  #checkov:skip=CKV_AWS_144:単一リージョン（東京）の方針。東京の障害時はサーバーも動かず、別リージョンの複製では遊べない。保存料金も約 2 倍になる。
  #checkov:skip=CKV_AWS_145:SSE-S3 の方針。aws/s3 鍵は鍵ポリシーを編集できず、カスタマーマネージドキーは予算に見合わない。
  #checkov:skip=CKV2_AWS_62:バックアップの成否はスクリプトから SNS の events に通知するため、S3 のイベント通知は重複する。
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "backup" {
  bucket = aws_s3_bucket.backup.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "RequireTls"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.backup]
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket     = aws_s3_bucket.backup.id
  depends_on = [aws_s3_bucket_versioning.backup]

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = var.noncurrent_version_days }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_logging" "backup" {
  bucket        = aws_s3_bucket.backup.id
  target_bucket = var.log_bucket_name
  # bootstrap のログバケットのポリシーは、このプレフィックスだけを許可している。
  target_prefix = "backup/"
}
