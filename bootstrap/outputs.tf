output "state_bucket_name" {
  description = "GitHub Variables の TF_STATE_BUCKET に登録する値"
  value       = aws_s3_bucket.state.id
}

output "plan_role_arn" {
  description = "GitHub Variables の AWS_PLAN_ROLE_ARN に登録する値"
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "GitHub Variables の AWS_APPLY_ROLE_ARN に登録する値"
  value       = aws_iam_role.apply.arn
}

output "ops_role_arn" {
  description = "GitHub Variables の AWS_OPS_ROLE_ARN に登録する値"
  value       = aws_iam_role.ops.arn
}

output "instance_boundary_arn" {
  description = "インスタンスロール用 permissions boundary の ARN"
  value       = aws_iam_policy.instance_boundary.arn
}

output "github_variables_commands" {
  description = "GitHub CLI で Variables を登録するコマンド"
  value       = <<-EOT
    gh variable set TF_STATE_BUCKET    --repo ${local.github_repo} --body "${aws_s3_bucket.state.id}"
    gh variable set AWS_PLAN_ROLE_ARN  --repo ${local.github_repo} --body "${aws_iam_role.plan.arn}"
    gh variable set AWS_APPLY_ROLE_ARN --repo ${local.github_repo} --body "${aws_iam_role.apply.arn}"
    gh variable set AWS_OPS_ROLE_ARN   --repo ${local.github_repo} --body "${aws_iam_role.ops.arn}"
  EOT
}
