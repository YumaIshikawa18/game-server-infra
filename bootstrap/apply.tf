locals {
  ec2_arn = "arn:${local.partition}:ec2:${var.region}:${local.account_id}"
  ec2_create_actions = [
    "ec2:CreateVpc", "ec2:CreateSubnet", "ec2:CreateInternetGateway", "ec2:CreateRouteTable",
    "ec2:CreateSecurityGroup", "ec2:CreateNetworkInterface", "ec2:CreateVolume", "ec2:AllocateAddress",
    "ec2:CreateFlowLogs",
  ]
  ec2_mutate_actions = [
    "ec2:DeleteVpc", "ec2:DeleteSubnet", "ec2:DeleteInternetGateway", "ec2:DeleteRouteTable",
    "ec2:DeleteSecurityGroup", "ec2:DeleteNetworkInterface", "ec2:DeleteVolume", "ec2:ReleaseAddress",
    "ec2:ModifyVpcAttribute", "ec2:ModifySubnetAttribute", "ec2:ModifyNetworkInterfaceAttribute",
    "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute", "ec2:AssociateRouteTable",
    "ec2:DisassociateRouteTable", "ec2:ReplaceRouteTableAssociation", "ec2:AttachInternetGateway",
    "ec2:DetachInternetGateway", "ec2:AssociateAddress", "ec2:DisassociateAddress",
    "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
    "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress", "ec2:ModifySecurityGroupRules",
    "ec2:AttachVolume", "ec2:DetachVolume", "ec2:ModifyVolume", "ec2:ModifyInstanceAttribute",
    "ec2:StartInstances", "ec2:StopInstances", "ec2:TerminateInstances",
    "ec2:AssociateIamInstanceProfile", "ec2:ReplaceIamInstanceProfileAssociation",
    "ec2:DisassociateIamInstanceProfile", "ec2:MonitorInstances", "ec2:UnmonitorInstances",
    "ec2:DeleteFlowLogs",
  ]
  apply_groups = {
    # 承認後の deploy は apply ロールで plan を作り直すため、plan ロールと同じ読み取りも必要（AMI の SSM パラメータなど）。
    reads = local.application_reads
    state = concat(local.state_read, local.operation_lock, [
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${local.state_bucket_arn}/${var.state_key}" },
      { Effect = "Deny", Action = ["iam:*"], Resource = [local.ci_role_arn, local.ci_policy_arn] },
      { Effect = "Deny", Action = ["iam:DeleteRolePermissionsBoundary"], Resource = local.app_role_arn },
    ])
    compute = concat([local.read_statement], [
      { Effect = "Allow", Action = local.ec2_create_actions, Resource = "${local.ec2_arn}:*/*", Condition = { StringEquals = { "aws:RequestTag/Project" = var.prefix } } },
      { Effect = "Allow", Action = local.ec2_mutate_actions, Resource = "${local.ec2_arn}:*/*", Condition = { StringEquals = { "ec2:ResourceTag/Project" = var.prefix } } },
      { Effect = "Allow", Action = ["ec2:RunInstances"], Resource = ["${local.ec2_arn}:instance/*", "${local.ec2_arn}:volume/*"], Condition = { StringEquals = { "aws:RequestTag/Project" = var.prefix } } },
      { Effect = "Allow", Action = ["ec2:RunInstances"], Resource = ["${local.ec2_arn}:subnet/*", "${local.ec2_arn}:security-group/*", "${local.ec2_arn}:network-interface/*"], Condition = { StringEquals = { "ec2:ResourceTag/Project" = var.prefix } } },
      { Effect = "Allow", Action = ["ec2:RunInstances"], Resource = "arn:${local.partition}:ec2:${var.region}::image/*" },
      { Effect = "Allow", Action = ["ec2:CreateTags"], Resource = "${local.ec2_arn}:*/*", Condition = { StringEquals = { "ec2:CreateAction" = [for action in concat(local.ec2_create_actions, ["ec2:RunInstances"]) : trimprefix(action, "ec2:")] } } },
      { Effect = "Allow", Action = ["ec2:CreateTags", "ec2:DeleteTags"], Resource = "${local.ec2_arn}:*/*", Condition = { StringEquals = { "ec2:ResourceTag/Project" = var.prefix } } },
      # S3 へのフローログ配信の登録。リソース単位の制限に非対応。
      { Effect = "Allow", Action = ["logs:CreateLogDelivery", "logs:DeleteLogDelivery"], Resource = "*" },
    ])
    identity = [
      { Effect = "Allow", Action = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"], Resource = local.app_role_arn, Condition = { StringEquals = { "iam:PermissionsBoundary" = "${local.account_arn}:policy/${var.prefix}-ci-boundary" } } },
      { Effect = "Allow", Action = ["iam:GetRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:DeleteRole", "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:TagRole", "iam:UntagRole"], Resource = local.app_role_arn },
      { Effect = "Allow", Action = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"], Resource = local.app_role_arn, Condition = { ArnLike = { "iam:PolicyARN" = ["${local.account_arn}:policy/${var.prefix}-app-*", "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"] } } },
      { Effect = "Allow", Action = ["iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile", "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile", "iam:UntagInstanceProfile"], Resource = "${local.account_arn}:instance-profile/${var.prefix}-app-*" },
      { Effect = "Allow", Action = ["iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:ListEntitiesForPolicy", "iam:TagPolicy", "iam:UntagPolicy"], Resource = "${local.account_arn}:policy/${var.prefix}-app-*" },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = "${local.account_arn}:role/${var.prefix}-app-server", Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } } },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = [for role in ["watchdog", "notifier"] : "${local.account_arn}:role/${var.prefix}-app-${role}"], Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } } },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = "${local.account_arn}:role/${var.prefix}-app-scheduler", Condition = { StringEquals = { "iam:PassedToService" = "scheduler.amazonaws.com" } } },
    ]
    storage = [
      { Effect = "Allow", Action = ["s3:CreateBucket", "s3:DeleteBucket", "s3:PutBucketTagging", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketPublicAccessBlock", "s3:PutEncryptionConfiguration", "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration", "s3:GetBucketPolicy", "s3:GetBucketPublicAccessBlock", "s3:GetEncryptionConfiguration", "s3:GetBucketVersioning", "s3:GetLifecycleConfiguration", "s3:GetBucketTagging", "s3:GetBucketLocation", "s3:ListBucket", "s3:PutBucketLogging", "s3:GetBucketLogging", "s3:PutBucketOwnershipControls", "s3:GetBucketOwnershipControls"], Resource = local.backup_arn },
      { Effect = "Allow", Action = local.bucket_refresh_reads, Resource = local.backup_arn },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:GetObjectTagging", "s3:PutObjectTagging"], Resource = "${local.backup_arn}/deploy/*" },
    ]
    services = concat([
      { Effect = "Allow", Action = ["ssm:SendCommand"], Resource = slice(local.app_resources.document, 0, 2) },
      local.ssm_commands[1], local.ssm_commands[2],
      ], [
      { Effect = "Allow", Action = ["ssm:CreateDocument", "ssm:UpdateDocument", "ssm:UpdateDocumentDefaultVersion", "ssm:DeleteDocument", "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource", "ssm:DescribeDocumentPermission"], Resource = local.app_resources.document },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource"], Resource = local.app_resources.logs },
      { Effect = "Allow", Action = ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:TagResource", "cloudwatch:UntagResource"], Resource = "arn:${local.partition}:cloudwatch:${var.region}:${local.account_id}:alarm:${var.prefix}-*" },
      { Effect = "Allow", Action = ["sns:CreateTopic", "sns:DeleteTopic", "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:ListTagsForResource", "sns:TagResource", "sns:UntagResource", "sns:Subscribe", "sns:ListSubscriptionsByTopic"], Resource = local.app_resources.sns },
      { Effect = "Allow", Action = ["sns:GetSubscriptionAttributes", "sns:SetSubscriptionAttributes", "sns:Unsubscribe"], Resource = "${local.app_resources.sns}:*" },
      { Effect = "Allow", Action = ["lambda:CreateFunction", "lambda:DeleteFunction", "lambda:GetFunction", "lambda:GetFunctionConfiguration", "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration", "lambda:ListVersionsByFunction", "lambda:GetPolicy", "lambda:AddPermission", "lambda:RemovePermission", "lambda:GetFunctionConcurrency", "lambda:PutFunctionConcurrency", "lambda:DeleteFunctionConcurrency", "lambda:ListTags", "lambda:TagResource", "lambda:UntagResource"], Resource = local.app_resources.lambda },
      { Effect = "Allow", Action = ["scheduler:CreateSchedule", "scheduler:GetSchedule", "scheduler:UpdateSchedule", "scheduler:DeleteSchedule", "scheduler:ListTagsForResource"], Resource = local.app_resources.scheduler },
      { Effect = "Allow", Action = ["budgets:ModifyBudget", "budgets:ViewBudget", "budgets:TagResource", "budgets:UntagResource", "budgets:ListTagsForResource"], Resource = "arn:${local.partition}:budgets::${local.account_id}:budget/${var.prefix}-*" },
      local.notify,
    ])
  }
}

# 管理ポリシーを分け、ポリシーごとの上限とロールの inline policy 合計上限を超えないようにする。
resource "aws_iam_policy" "apply" {
  for_each = toset(["reads", "state", "compute", "identity", "storage", "services"])
  name     = "${var.prefix}-ci-apply-${each.key}"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.apply_groups[each.key]
  })
}

# ポリシーの一覧から作り、ポリシーを足したのに付け忘れることがないようにする。
resource "aws_iam_role_policy_attachment" "apply" {
  for_each   = aws_iam_policy.apply
  role       = aws_iam_role.ci["apply"].name
  policy_arn = each.value.arn
}
