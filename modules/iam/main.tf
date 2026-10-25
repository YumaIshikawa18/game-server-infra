data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.name_prefix}-server"
  description          = "Minecraft server instance role"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  permissions_boundary = var.permissions_boundary_arn
}

# Session Manager / Run Command 用。Instance Connect を使わない場合の接続手段にもなる
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# AmazonSSMManagedInstanceCore は ssm:GetParameter を Resource "*" で許可しているが、
# 境界ポリシーで絞る前提でも意図を明示するため、読む対象のパラメータを列挙しておく。
# なお EC2 の停止は OS の shutdown（instance_initiated_shutdown_behavior = "stop"）で行うため、
# ec2:StopInstances は付与しない。
data "aws_iam_policy_document" "read_parameters" {
  statement {
    sid       = "ReadMinecraftParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = var.ssm_parameter_arns
  }
}

resource "aws_iam_role_policy" "read_parameters" {
  name   = "read-minecraft-parameters"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.read_parameters.json
}

resource "aws_iam_instance_profile" "this" {
  name = aws_iam_role.this.name
  role = aws_iam_role.this.name
}

data "aws_partition" "current" {}
