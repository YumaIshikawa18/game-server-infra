locals {
  github_oidc_host         = "token.actions.githubusercontent.com"
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # GitHub OIDC トークンの sub。ワークフローごとに使うロールを分け、それぞれの sub だけを信頼する
  #   plan : PR（pull_request）と既定ブランチ上の plan
  #   apply: GitHub Environment "prod"（Required reviewers で承認必須にする）
  #   ops  : GitHub Environment "prod-ops"（server-control 用）
  plan_subjects = [
    "repo:${local.github_repo}:pull_request",
    "repo:${local.github_repo}:ref:refs/heads/${var.github_default_branch}",
  ]
  apply_subjects = ["repo:${local.github_repo}:environment:${var.environment}"]
  ops_subjects   = ["repo:${local.github_repo}:environment:${var.ops_environment}"]
}

# thumbprint_list は AWS 側で GitHub の証明書を検証するようになったため省略する
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://${local.github_oidc_host}"
}

data "aws_iam_policy_document" "github_trust" {
  for_each = {
    plan  = local.plan_subjects
    apply = local.apply_subjects
    ops   = local.ops_subjects
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = each.value
    }
  }
}
