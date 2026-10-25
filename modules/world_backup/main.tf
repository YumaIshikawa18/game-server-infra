data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # bootstrap の apply ロール / 境界ポリシーは "<project>-*-world-backup-*" に一致するバケットだけを許可している
  bucket_name = "${var.name_prefix}-world-backup-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"
}

#trivy:ignore:AWS-0089 アクセスログ用バケットを別途持つほどの規模ではないため無効
#trivy:ignore:AWS-0090 世代管理はタイムスタンプ付きオブジェクトとライフサイクルで行う
resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#trivy:ignore:AWS-0132 KMS の CMK は月額費用がかかるため SSE-S3 を使う
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {
      prefix = "${var.object_prefix}/"
    }

    expiration {
      days = var.retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# インスタンスにはアップロードだけを許可する（読み出し・削除は人間が自分の権限で行う）
data "aws_iam_policy_document" "upload" {
  statement {
    sid       = "UploadWorldBackups"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.this.arn}/${var.object_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "upload" {
  name   = "upload-world-backups"
  role   = var.instance_role_name
  policy = data.aws_iam_policy_document.upload.json
}
