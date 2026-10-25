data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # envs/<environment> が作るリソースの名前の接頭辞（envs/prod の local.name_prefix と同じ規則）
  resource_prefix = "${var.project_name}-${var.environment}"

  state_bucket_name = coalesce(var.state_bucket_name, "${var.project_name}-tfstate-${local.account_id}-${var.region}")
  state_key_prefix  = "${var.project_name}/${var.environment}"

  github_repo = "${var.github_owner}/${var.github_repository}"
}
