mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  bucket_name     = "example-backup"
  log_bucket_name = "example-logs"
}

run "protects_backups" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.backup.block_public_acls && aws_s3_bucket_public_access_block.backup.block_public_policy && aws_s3_bucket_public_access_block.backup.ignore_public_acls && aws_s3_bucket_public_access_block.backup.restrict_public_buckets
    error_message = "バックアップバケットの公開を禁止してください。"
  }
  assert {
    condition     = one(aws_s3_bucket_versioning.backup.versioning_configuration).status == "Enabled"
    error_message = "誤削除に備えてバージョニングを有効にしてください。"
  }
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.backup.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "SSE-S3 で暗号化してください。"
  }
  assert {
    condition     = jsondecode(aws_s3_bucket_policy.backup.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false" && jsondecode(aws_s3_bucket_policy.backup.policy).Statement[0].Effect == "Deny"
    error_message = "TLS 以外のアクセスを拒否してください。"
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.backup.rule).noncurrent_version_expiration[0].noncurrent_days == 7 && one(aws_s3_bucket_lifecycle_configuration.backup.rule).abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "旧版と未完了アップロードは 7 日で削除してください。"
  }
  assert {
    condition     = aws_s3_bucket_logging.backup.target_bucket == "example-logs" && aws_s3_bucket_logging.backup.target_prefix == "backup/"
    error_message = "アクセスログはログバケットの backup/ に送ってください。"
  }
}

run "reject_invalid_bucket_name" {
  command = plan
  variables { bucket_name = "Invalid_Name" }
  expect_failures = [var.bucket_name]
}

run "reject_long_noncurrent_retention" {
  command = plan
  variables { noncurrent_version_days = 31 }
  expect_failures = [var.noncurrent_version_days]
}
