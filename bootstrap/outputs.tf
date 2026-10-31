output "ci_role_arns" {
  description = "GitHub Secrets に登録する plan / apply / ops ロール。"
  value       = { for key, role in aws_iam_role.ci : key => role.arn }
  sensitive   = true
}

output "permissions_boundary_arn" {
  description = "本番で作成する app ロールすべてに必須の permissions boundary。"
  value       = aws_iam_policy.boundary.arn
  sensitive   = true
}

output "state_bucket_name" {
  description = "state バックエンドのバケット。"
  value       = aws_s3_bucket.state.id
  sensitive   = true
}
