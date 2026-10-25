# terraform plan 用。ReadOnlyAccess を基本に、データそのものを読める操作を Deny で削る。
# plan は -lock=false で実行するため state バケットへの書き込み権限は持たない。
resource "aws_iam_role" "plan" {
  name               = "${var.project_name}-github-plan"
  description        = "GitHub Actions: terraform plan for ${local.github_repo}"
  assume_role_policy = data.aws_iam_policy_document.github_trust["plan"].json
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_restrictions" {
  statement {
    sid           = "DenyObjectReadExceptState"
    effect        = "Deny"
    actions       = ["s3:GetObject", "s3:GetObjectVersion"]
    not_resources = ["${aws_s3_bucket.state.arn}/${local.state_key_prefix}/*"]
  }

  statement {
    sid     = "DenyParameterReadExceptMinecraft"
    effect  = "Deny"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath", "ssm:GetParameterHistory"]
    not_resources = [
      "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter${var.ssm_parameter_prefix}/*",
      "arn:${local.partition}:ssm:${var.region}::parameter/aws/service/*",
    ]
  }

  statement {
    sid       = "DenySecretAndConsoleRead"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue", "ec2:GetPasswordData", "ec2:GetConsoleOutput", "ec2:GetConsoleScreenshot"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "plan_restrictions" {
  name   = "restrict-data-read"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_restrictions.json
}
