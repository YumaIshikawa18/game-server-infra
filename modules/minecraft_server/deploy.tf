# ホストが起動のたびに S3 の deploy/ から同期するファイル。user data（16 KB 上限）には同期処理だけを書く。
# 設定を変えて apply した内容は、次の起動から反映される。
locals {
  static_files = {
    for relative in fileset("${path.module}/files", "**") : relative => file("${path.module}/files/${relative}")
  }
  minecraft_env = {
    EULA                    = var.accept_minecraft_eula ? "TRUE" : "FALSE"
    TYPE                    = upper(var.loader == "vanilla" ? "VANILLA" : var.loader)
    VERSION                 = var.minecraft_version
    MEMORY                  = "${local.heap_gb}G"
    USE_AIKAR_FLAGS         = "true"
    ONLINE_MODE             = "TRUE"
    ENABLE_WHITELIST        = "TRUE"
    ENFORCE_WHITELIST       = "TRUE"
    EXISTING_WHITELIST_FILE = "SYNCHRONIZE"
    ENABLE_RCON             = "true"
    MAX_PLAYERS             = tostring(var.game_settings.max_players)
    VIEW_DISTANCE           = tostring(var.game_settings.view_distance)
    SIMULATION_DISTANCE     = tostring(var.game_settings.simulation_distance)
    DIFFICULTY              = var.game_settings.difficulty
    MOTD                    = var.game_settings.motd
    TZ                      = "Asia/Tokyo"
  }
  loader_env = {
    vanilla  = {}
    fabric   = { FABRIC_LOADER_VERSION = coalesce(var.loader_version, "-") }
    forge    = { FORGE_VERSION = coalesce(var.loader_version, "-") }
    neoforge = { NEOFORGE_VERSION = coalesce(var.loader_version, "-") }
  }
  cloudwatch_agent = {
    agent = { metrics_collection_interval = 60, omit_hostname = true, run_as_user = "root" }
    metrics = {
      namespace = "Minecraft"
      metrics_collected = {
        disk = { measurement = ["used_percent"], resources = ["/srv/minecraft"], drop_device = true }
      }
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [{
            file_path       = "/var/log/minecraft/scripts.log"
            log_group_name  = local.log_groups.scripts
            log_stream_name = "{instance_id}"
          }]
        }
      }
    }
  }
  generated_files = {
    "compose.yml" = var.compose_file
    "compose.env" = join("", [for key, value in {
      MC_REGION           = var.region
      MC_SERVER_LOG_GROUP = local.log_groups.server
      MC_LOG_STREAM       = "minecraft"
    } : "${key}=${value}\n"])
    "minecraft.env" = join("", [for key, value in merge(local.minecraft_env, local.loader_env[var.loader]) : "${key}=${value}\n"])
    "host.env" = join("", [for key, value in {
      MC_REGION       = var.region
      MC_BUCKET       = var.backup_bucket_name
      MC_TOPIC_ARN    = var.events_topic_arn
      MC_PARAM_PREFIX = local.param_prefix
    } : "${key}=${value}\n"])
    "config/mods.json"             = jsonencode(var.mods)
    "config/cloudwatch-agent.json" = jsonencode(local.cloudwatch_agent)
  }
  deploy_files = merge(local.static_files, local.generated_files)
}

resource "aws_s3_object" "deploy" {
  # キーに秘匿値は含まれないが、値は prefix などを含むため sensitive として扱う。
  for_each               = nonsensitive(toset(keys(local.deploy_files)))
  bucket                 = var.backup_bucket_name
  key                    = "deploy/${each.key}"
  content                = local.deploy_files[each.key]
  server_side_encryption = "AES256"
}
