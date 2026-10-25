################################################################################
# 共通
################################################################################

variable "region" {
  description = "AWS リージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "プロジェクト名。リソース名の接頭辞とタグに使う（bootstrap の project_name と揃えること）"
  type        = string
  default     = "minecraft"
}

variable "environment" {
  description = "環境名"
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "全リソースに付ける追加タグ（Project / Environment / ManagedBy は自動で付く）"
  type        = map(string)
  default     = {}
}

################################################################################
# ネットワーク
################################################################################

variable "use_default_vpc" {
  description = "true なら既定 VPC を使い、false なら専用 VPC を作る"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "専用 VPC の CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "パブリックサブネットの CIDR"
  type        = string
  default     = "10.0.0.0/24"
}

variable "availability_zone" {
  description = "配置する AZ。null ならインスタンスタイプを提供している AZ から自動で選ぶ"
  type        = string
  default     = null
}

variable "enable_ssh" {
  description = "EC2 Instance Connect 用に 22/TCP を開けるか。false でも Session Manager で接続できる"
  type        = bool
  default     = true
}

variable "instance_connect_cidrs" {
  description = "SSH を許可する CIDR。null なら ip-ranges.json の EC2_INSTANCE_CONNECT（region）を使う"
  type        = list(string)
  default     = null
}

################################################################################
# EC2 / EBS
################################################################################

# 同時接続人数ごとのインスタンスタイプの目安（AWS ブログより）
#   1〜4 人  : t4g.small  (2 vCPU / 2 GiB)  jvm_memory_mb = 1300
#   4〜8 人  : t4g.medium (2 vCPU / 4 GiB)  jvm_memory_mb = 3000 程度
#   8〜16 人 : t4g.large  (2 vCPU / 8 GiB)  jvm_memory_mb = 6500 程度
#   16〜32 人: r8g.large  (2 vCPU / 16 GiB) jvm_memory_mb = 14000 程度
# jvm_memory_mb の値は、OS 用に 512MB 以上を残す前提で決めた目安
variable "instance_type" {
  description = "EC2 インスタンスタイプ（arm64 / x86_64 のどちらでもよい）"
  type        = string
  default     = "t4g.small"
}

variable "cpu_credits" {
  description = "T 系インスタンスの CPU クレジット。unlimited（AWS の既定）は高負荷が続くと追加課金がある"
  type        = string
  default     = "unlimited"
}

variable "root_volume_size" {
  description = "ルート EBS のサイズ（GiB）"
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "Amazon Linux 2023 の AMI は 8GiB 以上が必要です。"
  }
}

variable "data_volume_size" {
  description = "ワールド用 EBS のサイズ（GiB）"
  type        = number
  default     = 8

  validation {
    condition     = var.data_volume_size >= 1
    error_message = "data_volume_size は 1 以上を指定してください。"
  }
}

variable "data_volume_final_snapshot" {
  description = "destroy でワールド用 EBS を消す前にスナップショットを残すか"
  type        = bool
  default     = true
}

variable "use_eip" {
  description = "Elastic IP を使うか。false にすると停止・起動のたびに接続先 IP が変わる"
  type        = bool
  default     = true
}

variable "use_instance_permissions_boundary" {
  description = "bootstrap で作成した <project_name>-instance-boundary をインスタンスロールに付けるか（CD の apply ロールは付与を必須にしている）"
  type        = bool
  default     = true
}

################################################################################
# Minecraft
################################################################################

variable "minecraft_version" {
  description = "Minecraft Java サーバーのバージョン。version_manifest_v2.json の id（例: 26.3）か latest"
  type        = string
  default     = "26.3"

  validation {
    condition     = can(regex("^(latest|[0-9][0-9A-Za-z.\\-_ ]*)$", var.minecraft_version))
    error_message = "minecraft_version は 26.3 のようなバージョン ID か latest を指定してください。"
  }
}

variable "accept_eula" {
  description = "Minecraft EULA（https://aka.ms/MinecraftEULA）を読んで同意する場合のみ true にする"
  type        = bool
  default     = false
}

variable "minecraft_port" {
  description = "Minecraft サーバーの待ち受けポート"
  type        = number
  default     = 25565
}

variable "jvm_memory_mb" {
  description = "JVM ヒープサイズ（-Xms/-Xmx、MB）。/mc/ram に入る"
  type        = number
  default     = 1300

  validation {
    condition     = var.jvm_memory_mb >= 512
    error_message = "jvm_memory_mb は 512 以上を指定してください。"
  }
}

variable "shutdown_timer_seconds" {
  description = "無人のままこの秒数がたつと EC2 を停止する。/mc/shutdowntimer に入る"
  type        = number
  default     = 900

  validation {
    condition     = var.shutdown_timer_seconds >= 300
    error_message = "短すぎるとプレイヤーが入る前に停止するため、300 秒以上を指定してください。"
  }
}

variable "ssm_parameter_prefix" {
  description = "SSM パラメータ名の接頭辞（bootstrap の ssm_parameter_prefix と揃えること）"
  type        = string
  default     = "/mc"
}

################################################################################
# バックアップ（任意）
################################################################################

variable "enable_backup" {
  description = "ワールドを S3 に日次でバックアップするか（自動停止の直前にも取得する）"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "バックアップの保持日数"
  type        = number
  default     = 30
}

variable "backup_on_calendar" {
  description = "日次バックアップの systemd OnCalendar 式（UTC）。既定は JST 03:00"
  type        = string
  default     = "*-*-* 18:00:00"
}

variable "backup_force_destroy" {
  description = "destroy 時にバックアップが残っていてもバケットを削除するか"
  type        = bool
  default     = false
}

variable "allowed_account_ids" {
  description = "操作を許可する AWS アカウント ID。個人情報として扱うためリポジトリには書かず、ローカルは *.auto.tfvars、CI は Secrets（AWS_ACCOUNT_ID）から渡す。null ならチェックしない"
  type        = list(string)
  default     = null

  validation {
    condition     = alltrue([for id in coalesce(var.allowed_account_ids, []) : can(regex("^[0-9]{12}$", id))])
    error_message = "allowed_account_ids には 12 桁の AWS アカウント ID を指定してください。"
  }
}
