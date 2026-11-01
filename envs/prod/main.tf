# 本番環境。ゲームの設定（バージョン・ローダー・MOD・server.properties 相当）は PR で変更する（FR2.1）。
locals {
  minecraft = {
    # 2026-11-01 時点の最新リリース。Java 25 が必要で、docker/compose.yml のイメージと合わせる。
    version        = "26.3"
    loader         = "vanilla"
    loader_version = null
    # { name, url, sha256, side = server | client | both }。sha256 を照合してから配置する。
    mods = []
    settings = {
      max_players         = 10
      view_distance       = 10
      simulation_distance = 8
      difficulty          = "normal"
      motd                = "Minecraft"
    }
  }
  lambda_build_dir = "${path.root}/.build"
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  permissions_boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.prefix}-ci-boundary"
}

module "network" {
  source               = "../../modules/network"
  prefix               = var.prefix
  vpc_cidr             = "10.20.0.0/24"
  availability_zone    = var.availability_zone
  flow_log_bucket_name = var.log_bucket_name
}

module "world_backup" {
  source          = "../../modules/world_backup"
  bucket_name     = var.backup_bucket_name
  log_bucket_name = var.log_bucket_name
}

module "notifier" {
  source                   = "../../modules/notifier"
  prefix                   = var.prefix
  region                   = var.region
  notification_email       = var.notification_email
  webhook_parameter_name   = "/${var.prefix}/minecraft/discord-webhook"
  permissions_boundary_arn = local.permissions_boundary_arn
  source_dir               = "${path.root}/../../lambda/notifier"
  build_dir                = local.lambda_build_dir
}

module "minecraft_server" {
  source                   = "../../modules/minecraft_server"
  prefix                   = var.prefix
  region                   = var.region
  subnet_id                = module.network.subnet_id
  availability_zone        = var.availability_zone
  security_group_id        = module.network.security_group_id
  backup_bucket_name       = module.world_backup.bucket_name
  events_topic_arn         = module.notifier.events_topic_arn
  permissions_boundary_arn = local.permissions_boundary_arn
  accept_minecraft_eula    = var.accept_minecraft_eula
  minecraft_version        = local.minecraft.version
  loader                   = local.minecraft.loader
  loader_version           = local.minecraft.loader_version
  mods                     = local.minecraft.mods
  game_settings            = local.minecraft.settings
  compose_file             = file("${path.root}/../../docker/compose.yml")
}

module "watchdog" {
  source                   = "../../modules/watchdog"
  prefix                   = var.prefix
  region                   = var.region
  events_topic_arn         = module.notifier.events_topic_arn
  permissions_boundary_arn = local.permissions_boundary_arn
  source_dir               = "${path.root}/../../lambda/watchdog"
  build_dir                = local.lambda_build_dir
}

module "monitoring" {
  source             = "../../modules/monitoring"
  prefix             = var.prefix
  alerts_topic_arn   = module.notifier.alerts_topic_arn
  monthly_budget_usd = var.monthly_budget_usd
}
