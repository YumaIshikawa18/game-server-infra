data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# EC2 Instance Connect の送信元 CIDR（ip-ranges.json の EC2_INSTANCE_CONNECT）
data "aws_ip_ranges" "instance_connect" {
  count = var.enable_ssh && var.instance_connect_cidrs == null ? 1 : 0

  regions  = [var.region]
  services = ["ec2_instance_connect"]
}

# インスタンスタイプを提供している AZ から 1 つ選ぶ（t4g は全 AZ にあるとは限らない）
data "aws_ec2_instance_type_offerings" "this" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

locals {
  name_prefix       = "${var.project_name}-${var.environment}"
  availability_zone = coalesce(var.availability_zone, sort(data.aws_ec2_instance_type_offerings.this.locations)[0])

  ssh_ingress_cidrs = !var.enable_ssh ? [] : coalesce(var.instance_connect_cidrs, one(data.aws_ip_ranges.instance_connect[*].cidr_blocks))

  permissions_boundary_arn = !var.use_instance_permissions_boundary ? null : format(
    "arn:%s:iam::%s:policy/%s-instance-boundary",
    data.aws_partition.current.partition,
    data.aws_caller_identity.current.account_id,
    var.project_name,
  )
}

module "network" {
  source = "../../modules/network"

  name_prefix        = local.name_prefix
  use_default_vpc    = var.use_default_vpc
  availability_zone  = local.availability_zone
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
}

module "security_group" {
  source = "../../modules/security_group"

  name_prefix       = local.name_prefix
  vpc_id            = module.network.vpc_id
  minecraft_port    = var.minecraft_port
  ssh_ingress_cidrs = local.ssh_ingress_cidrs
}

module "ssm_parameters" {
  source = "../../modules/ssm_parameters"

  parameter_prefix       = var.ssm_parameter_prefix
  jvm_memory_mb          = var.jvm_memory_mb
  shutdown_timer_seconds = var.shutdown_timer_seconds
}

module "iam" {
  source = "../../modules/iam"

  name_prefix              = local.name_prefix
  ssm_parameter_arns       = module.ssm_parameters.parameter_arns
  permissions_boundary_arn = local.permissions_boundary_arn
}

module "world_backup" {
  source = "../../modules/world_backup"
  count  = var.enable_backup ? 1 : 0

  name_prefix        = local.name_prefix
  instance_role_name = module.iam.role_name
  retention_days     = var.backup_retention_days
  force_destroy      = var.backup_force_destroy
}

module "minecraft_server" {
  source = "../../modules/minecraft_server"

  name_prefix           = local.name_prefix
  instance_type         = var.instance_type
  subnet_id             = module.network.subnet_id
  security_group_ids    = [module.security_group.security_group_id]
  instance_profile_name = module.iam.instance_profile_name

  root_volume_size           = var.root_volume_size
  data_volume_size           = var.data_volume_size
  data_volume_final_snapshot = var.data_volume_final_snapshot
  cpu_credits                = var.cpu_credits
  use_eip                    = var.use_eip

  minecraft_version = var.minecraft_version
  accept_eula       = var.accept_eula
  minecraft_port    = var.minecraft_port

  jvm_memory_mb                 = var.jvm_memory_mb
  ram_parameter_name            = module.ssm_parameters.ram_parameter_name
  shutdown_timer_seconds        = var.shutdown_timer_seconds
  shutdown_timer_parameter_name = module.ssm_parameters.shutdown_timer_parameter_name

  backup_s3_uri      = var.enable_backup ? module.world_backup[0].s3_uri : null
  backup_on_calendar = var.backup_on_calendar
}
