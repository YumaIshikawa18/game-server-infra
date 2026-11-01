output "bucket_name" {
  description = "バックアップ・配布バケット名。"
  value       = aws_s3_bucket.backup.bucket
  sensitive   = true
}

output "bucket_arn" {
  description = "バックアップ・配布バケットの ARN。IAM ポリシーの対象に使う。"
  value       = local.bucket_arn
  sensitive   = true
}
