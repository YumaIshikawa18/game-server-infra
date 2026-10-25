# server-control ワークフロー用。タグで対象を Minecraft サーバーに限定し、起動・停止・状態確認だけを許可する
resource "aws_iam_role" "ops" {
  name               = "${var.project_name}-github-ops"
  description        = "GitHub Actions: start/stop/status for ${local.github_repo} (${var.environment})"
  assume_role_policy = data.aws_iam_policy_document.github_trust["ops"].json
}

data "aws_iam_policy_document" "ops" {
  statement {
    sid       = "DescribeInstances"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "StartStopMinecraftServer"
    actions   = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = ["arn:${local.partition}:ec2:${var.region}:${local.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [var.environment]
    }
  }

  # status は envs/prod が作る読み取り専用ドキュメントだけを実行できる
  statement {
    sid       = "SendStatusDocument"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:${local.partition}:ssm:${var.region}:${local.account_id}:document/${local.resource_prefix}-server-status"]
  }

  statement {
    sid       = "SendCommandToMinecraftServer"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:${local.partition}:ec2:${var.region}:${local.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Project"
      values   = [var.project_name]
    }

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Environment"
      values   = [var.environment]
    }
  }

  statement {
    sid       = "ReadCommandResult"
    actions   = ["ssm:GetCommandInvocation"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ops" {
  name   = "server-control-${var.environment}"
  role   = aws_iam_role.ops.id
  policy = data.aws_iam_policy_document.ops.json
}
