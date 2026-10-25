# envs/prod が作るインスタンスロールの permissions boundary。
# apply ロールはこの boundary を付けたロールしか作れないため、CI 経由で強い権限のロールは作れない。
# 内容は AmazonSSMManagedInstanceCore（ssm:GetParameter* は Minecraft 用に限定）とバックアップのアップロード。
data "aws_iam_policy_document" "instance_boundary" {
  statement {
    sid = "SsmManagedInstanceCore"
    actions = [
      "ssm:DescribeAssociation",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:DescribeDocument",
      "ssm:GetManifest",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadMinecraftParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [local.ssm_parameter_arn]
  }

  statement {
    sid       = "UploadWorldBackups"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${local.backup_bucket_arn}/*"]
  }
}

resource "aws_iam_policy" "instance_boundary" {
  name        = "${var.project_name}-instance-boundary"
  description = "Permissions boundary for ${var.project_name} EC2 instance roles"
  policy      = data.aws_iam_policy_document.instance_boundary.json
}
