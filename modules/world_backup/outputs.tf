output "bucket_name" {
  description = "バックアップ用 S3 バケット名"
  value       = aws_s3_bucket.this.id
}

output "s3_uri" {
  description = "バックアップの保存先 URI"
  value       = "s3://${aws_s3_bucket.this.id}/${var.object_prefix}"
}
