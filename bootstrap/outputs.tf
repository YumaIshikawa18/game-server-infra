output "state_bucket_name" {
  description = "GitHub Secrets の TF_STATE_BUCKET に登録する値"
  value       = aws_s3_bucket.state.id
}

output "plan_role_arn" {
  description = "GitHub Secrets の AWS_PLAN_ROLE_ARN に登録する値"
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "GitHub Secrets の AWS_APPLY_ROLE_ARN に登録する値"
  value       = aws_iam_role.apply.arn
}

output "ops_role_arn" {
  description = "GitHub Secrets の AWS_OPS_ROLE_ARN に登録する値"
  value       = aws_iam_role.ops.arn
}

output "instance_boundary_arn" {
  description = "インスタンスロール用 permissions boundary の ARN"
  value       = aws_iam_policy.instance_boundary.arn
}

# アカウント ID を含む値はすべて Secrets にする（public リポジトリのログでマスクされる）
output "github_secrets_commands" {
  description = "GitHub CLI で Secrets を登録するコマンド"
  value       = <<-EOT
    gh secret set AWS_ACCOUNT_ID     --repo ${local.github_repo} --body "${local.account_id}"
    gh secret set TF_STATE_BUCKET    --repo ${local.github_repo} --body "${aws_s3_bucket.state.id}"
    gh secret set AWS_PLAN_ROLE_ARN  --repo ${local.github_repo} --body "${aws_iam_role.plan.arn}"
    gh secret set AWS_APPLY_ROLE_ARN --repo ${local.github_repo} --body "${aws_iam_role.apply.arn}"
    gh secret set AWS_OPS_ROLE_ARN   --repo ${local.github_repo} --body "${aws_iam_role.ops.arn}"
  EOT
}
