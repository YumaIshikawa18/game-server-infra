# terraform apply / destroy 用（GitHub Environment "prod" からのみ引き受けられる）。
# envs/prod が作るリソースの名前（<project>-<environment>-*）とリージョンで権限を絞る。
resource "aws_iam_role" "apply" {
  name               = "${var.project_name}-github-apply"
  description        = "GitHub Actions: terraform apply for ${local.github_repo} (${var.environment})"
  assume_role_policy = data.aws_iam_policy_document.github_trust["apply"].json
}

locals {
  instance_role_arn    = "arn:${local.partition}:iam::${local.account_id}:role/${local.resource_prefix}-*"
  instance_profile_arn = "arn:${local.partition}:iam::${local.account_id}:instance-profile/${local.resource_prefix}-*"
  backup_bucket_arn    = "arn:${local.partition}:s3:::${local.resource_prefix}-world-backup-*"
  ssm_parameter_arn    = "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter${var.ssm_parameter_prefix}/*"
  ssm_document_arn     = "arn:${local.partition}:ssm:${var.region}:${local.account_id}:document/${local.resource_prefix}-*"
}

data "aws_iam_policy_document" "apply" {
  statement {
    sid       = "TerraformState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/${local.state_key_prefix}/*"]
  }

  statement {
    sid       = "TerraformStateList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  # VPC / SG / EC2 / EBS / EIP。EC2 はリソース単位の制御が煩雑なためリージョンで絞る
  statement {
    sid       = "Ec2InRegion"
    actions   = ["ec2:*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid = "ReadIam"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:GetInstanceProfile",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [local.instance_role_arn, local.instance_profile_arn]
  }

  # 権限を付与する操作は、インスタンス用の permissions boundary が付いている場合だけ許可する（権限昇格の防止）
  statement {
    sid = "ManageInstanceRoleWithBoundary"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = [local.instance_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.instance_boundary.arn]
    }
  }

  statement {
    sid       = "AttachOnlySsmCore"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = [local.instance_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.instance_boundary.arn]
    }

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"]
    }
  }

  statement {
    sid = "ManageInstanceRole"
    actions = [
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:TagRole",
      "iam:UntagRole",
    ]
    resources = [local.instance_role_arn]
  }

  statement {
    sid = "ManageInstanceProfile"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
    ]
    resources = [local.instance_profile_arn]
  }

  statement {
    sid       = "PassInstanceRoleToEc2"
    actions   = ["iam:PassRole"]
    resources = [local.instance_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid    = "ManageMinecraftParameters"
    effect = "Allow"
    actions = [
      "ssm:PutParameter",
      "ssm:DeleteParameter",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
      "ssm:ListTagsForResource",
    ]
    resources = [local.ssm_parameter_arn]
  }

  statement {
    sid       = "DescribeParameters"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadAmiParameter"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:${local.partition}:ssm:${var.region}::parameter/aws/service/ami-amazon-linux-latest/*"]
  }

  statement {
    sid = "ManageStatusDocument"
    actions = [
      "ssm:CreateDocument",
      "ssm:DeleteDocument",
      "ssm:UpdateDocument",
      "ssm:UpdateDocumentDefaultVersion",
      "ssm:DescribeDocument",
      "ssm:DescribeDocumentPermission",
      "ssm:GetDocument",
      "ssm:ListDocumentVersions",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
      "ssm:ListTagsForResource",
    ]
    resources = [local.ssm_document_arn]
  }

  # バックアップ用バケットの作成・設定・削除（force_destroy 時のオブジェクト削除を含む）
  statement {
    sid = "ManageBackupBucket"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:Get*",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:PutBucket*",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
    ]
    resources = [
      local.backup_bucket_arn,
      "${local.backup_bucket_arn}/*",
    ]
  }

  statement {
    sid       = "DenyBoundaryRemoval"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "terraform-apply-${var.environment}"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}
