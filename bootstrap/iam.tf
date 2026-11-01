locals {
  # var.github_repository は validation で owner/repo 形式を保証済み。
  ci_subjects = {
    plan  = ["repo:${var.github_repository}:pull_request", "repo:${var.github_repository}:ref:refs/heads/master"]
    apply = ["repo:${var.github_repository}:environment:prod"]
    ops   = ["repo:${var.github_repository}:environment:ops"]
  }
  app_resources = {
    ssm       = "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter/${var.prefix}/*"
    logs      = "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/${var.prefix}/*"
    sns       = "arn:${local.partition}:sns:${var.region}:${local.account_id}:${var.prefix}-*"
    lambda    = "arn:${local.partition}:lambda:${var.region}:${local.account_id}:function:${var.prefix}-*"
    scheduler = "arn:${local.partition}:scheduler:${var.region}:${local.account_id}:schedule/default/${var.prefix}-*"
    document  = [for name in ["mc-stop", "mc-health-check", "mc-restore-apply"] : "arn:${local.partition}:ssm:${var.region}:${local.account_id}:document/${name}"]
    instance  = "arn:${local.partition}:ec2:${var.region}:${local.account_id}:instance/*"
  }
  describe_actions = [
    "ec2:DescribeAccountAttributes", "ec2:DescribeAddresses", "ec2:DescribeAvailabilityZones",
    "ec2:DescribeIamInstanceProfileAssociations", "ec2:DescribeImages", "ec2:DescribeInstanceAttribute",
    "ec2:DescribeInstances", "ec2:DescribeInstanceStatus", "ec2:DescribeInstanceTypes",
    "ec2:DescribeInternetGateways", "ec2:DescribeNetworkAcls", "ec2:DescribeNetworkInterfaces",
    "ec2:DescribeRouteTables", "ec2:DescribeSecurityGroupRules", "ec2:DescribeSecurityGroups",
    "ec2:DescribeSubnets", "ec2:DescribeTags", "ec2:DescribeVolumes", "ec2:DescribeVolumesModifications",
    "ec2:DescribeVpcAttribute", "ec2:DescribeVpcs", "ssm:DescribeInstanceInformation",
    "ssm:GetCommandInvocation", "ssm:ListDocuments", "ssm:DescribeDocument", "ssm:GetDocument",
    "ssm:ListTagsForResource", "ec2:DescribeFlowLogs", "ec2:DescribeAddressesAttribute", "iam:ListPolicies", "iam:ListRoles", "iam:ListInstanceProfiles",
    "cloudwatch:DescribeAlarms", "cloudwatch:ListTagsForResource", "logs:DescribeLogGroups",
    "logs:ListTagsForResource", "sns:ListTopics", "sns:ListSubscriptions",
  ]
  # Describe/List、SSM agent の通信チャネル、CloudWatch metric API はリソース ARN による制限に非対応。
  read_statement = {
    Sid = "ProviderDiscovery", Effect = "Allow", Action = local.describe_actions, Resource = "*"
  }
  state_read = [
    { Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"], Resource = local.state_bucket_arn },
    { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${local.state_bucket_arn}/${var.state_key}" },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${local.state_bucket_arn}/${var.state_key}.tflock" },
  ]
  operation_lock = [
    {
      Effect    = "Allow", Action = ["s3:PutObject"], Resource = "${local.state_bucket_arn}/${var.lock_key}"
      Condition = { StringEquals = { "s3:if-none-match" = "*", "s3:x-amz-server-side-encryption" = "AES256" } }
    },
    {
      Effect    = "Allow", Action = ["s3:DeleteObject"], Resource = "${local.state_bucket_arn}/${var.lock_key}"
      Condition = { Null = { "s3:if-match" = "false" } }
    },
  ]
  managed_instance_condition = { StringEquals = { "ec2:ResourceTag/Project" = var.prefix, "ec2:ResourceTag/mc:managed" = "true" } }
  ssm_commands = [
    { Effect = "Allow", Action = ["ssm:SendCommand"], Resource = local.app_resources.document },
    { Effect = "Allow", Action = ["ssm:SendCommand"], Resource = local.app_resources.instance, Condition = { StringEquals = { "ssm:resourceTag/Project" = var.prefix, "ssm:resourceTag/mc:managed" = "true" } } },
    # RunCommand 結果と managed-instance のオンライン状態は参照 API のため Resource は *。
    { Effect = "Allow", Action = ["ssm:GetCommandInvocation", "ssm:DescribeInstanceInformation"], Resource = "*" },
  ]
  notify = { Effect = "Allow", Action = ["sns:Publish"], Resource = "arn:${local.partition}:sns:${var.region}:${local.account_id}:${var.prefix}-events" }
}

# 値を each.value で渡すと、Checkov が sub の値を静的に評価できる（map の添字参照は評価されない）。
resource "aws_iam_role" "ci" {
  for_each = local.ci_subjects
  name     = "${var.prefix}-ci-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.github_oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = each.value
      } }
    }]
  })
  max_session_duration = 3600
}

resource "aws_iam_policy" "boundary" {
  name = "${var.prefix}-ci-boundary"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${local.backup_arn}/hourly/*", "${local.backup_arn}/stop/*", "${local.backup_arn}/deploy/*"] },
      { Effect = "Allow", Action = ["s3:ListBucket", "s3:ListBucketVersions"], Resource = local.backup_arn },
      { Effect = "Allow", Action = ["ssm:GetParameter", "ssm:GetParameters"], Resource = local.app_resources.ssm },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = "arn:${local.partition}:kms:${var.region}:${local.account_id}:key/*", Condition = { StringEquals = { "kms:ViaService" = "ssm.${var.region}.amazonaws.com" }, StringLike = { "kms:EncryptionContext:PARAMETER_ARN" = local.app_resources.ssm } } },
      { Effect = "Allow", Action = ["ec2:StopInstances", "ec2:CreateTags", "ec2:DeleteTags"], Resource = local.app_resources.instance, Condition = local.managed_instance_condition },
      { Effect = "Allow", Action = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus", "ec2:DescribeTags", "cloudwatch:GetMetricData"], Resource = "*" },
      { Effect = "Allow", Action = ["cloudwatch:PutMetricData"], Resource = "*", Condition = { StringEquals = { "cloudwatch:namespace" = "Minecraft" } } },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"], Resource = local.app_resources.logs },
      { Effect = "Allow", Action = ["ssm:UpdateInstanceInformation"], Resource = local.app_resources.instance },
      # ssmmessages はリソース単位の制限に非対応（Session Manager の公式ポリシー例も Resource = "*"）。
      { Effect = "Allow", Action = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"], Resource = "*" },
      { Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = local.app_resources.lambda },
      local.notify,
    ]
  })
}

locals {
  # aws_s3_bucket の refresh が読む設定（未設定でも読み取りが必要）。
  bucket_refresh_reads = [
    "s3:GetBucketAcl", "s3:GetBucketCORS", "s3:GetBucketWebsite", "s3:GetAccelerateConfiguration",
    "s3:GetBucketRequestPayment", "s3:GetReplicationConfiguration", "s3:GetBucketObjectLockConfiguration",
  ]
  application_reads = [
    { Effect = "Allow", Action = ["ssm:GetParameter"], Resource = ["arn:${local.partition}:ssm:${var.region}::parameter/aws/service/ami-amazon-linux-latest/*"] },
    { Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:GetBucketPolicy", "s3:GetBucketPublicAccessBlock", "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration", "s3:GetBucketTagging", "s3:GetBucketLogging", "s3:GetBucketOwnershipControls"], Resource = local.backup_arn },
    { Effect = "Allow", Action = local.bucket_refresh_reads, Resource = local.backup_arn },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectAttributes", "s3:GetObjectTagging"], Resource = "${local.backup_arn}/deploy/*" },
    { Effect = "Allow", Action = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:GetInstanceProfile", "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:ListEntitiesForPolicy"], Resource = [local.app_role_arn, "${local.account_arn}:instance-profile/${var.prefix}-app-*", "${local.account_arn}:policy/${var.prefix}-app-*", "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"] },
    { Effect = "Allow", Action = ["lambda:GetFunction", "lambda:GetFunctionConfiguration", "lambda:GetPolicy", "lambda:ListTags", "lambda:GetFunctionConcurrency"], Resource = local.app_resources.lambda },
    { Effect = "Allow", Action = ["scheduler:GetSchedule", "scheduler:ListTagsForResource"], Resource = local.app_resources.scheduler },
    { Effect = "Allow", Action = ["sns:GetTopicAttributes", "sns:ListTagsForResource", "sns:ListSubscriptionsByTopic"], Resource = local.app_resources.sns },
    { Effect = "Allow", Action = ["sns:GetSubscriptionAttributes"], Resource = "${local.app_resources.sns}:*" },
    { Effect = "Allow", Action = ["budgets:ViewBudget"], Resource = "arn:${local.partition}:budgets::${local.account_id}:budget/${var.prefix}-*" },
    { Effect = "Allow", Action = ["ssm:DescribeDocumentPermission"], Resource = local.app_resources.document },
  ]
}

resource "aws_iam_role_policy" "plan" {
  role = aws_iam_role.ci["plan"].id
  name = "${var.prefix}-ci-plan"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat([local.read_statement], local.state_read, local.application_reads)
  })
}

resource "aws_iam_role_policy" "ops" {
  role = aws_iam_role.ci["ops"].id
  name = "${var.prefix}-ci-ops"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.operation_lock, local.ssm_commands, [
      { Effect = "Allow", Action = ["ec2:StartInstances", "ec2:StopInstances"], Resource = local.app_resources.instance, Condition = local.managed_instance_condition },
      { Effect = "Allow", Action = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus"], Resource = "*" },
      { Effect = "Allow", Action = ["ec2:CreateTags", "ec2:DeleteTags"], Resource = local.app_resources.instance, Condition = merge(local.managed_instance_condition, { "ForAllValues:StringEquals" = { "aws:TagKeys" = ["mc:mode"] } }) },
      local.notify,
    ])
  })
}
