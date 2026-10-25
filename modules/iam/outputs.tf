output "role_name" {
  description = "インスタンスロール名"
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "インスタンスロールの ARN"
  value       = aws_iam_role.this.arn
}

output "instance_profile_name" {
  description = "インスタンスプロファイル名"
  value       = aws_iam_instance_profile.this.name
}
