variable "name_prefix" {
  description = "リソース名の接頭辞"
  type        = string
}

variable "instance_type" {
  description = "EC2 インスタンスタイプ"
  type        = string
}

variable "subnet_id" {
  description = "インスタンスを配置するパブリックサブネットの ID"
  type        = string
}

variable "security_group_ids" {
  description = "インスタンスに付けるセキュリティグループ"
  type        = list(string)
}

variable "instance_profile_name" {
  description = "インスタンスプロファイル名"
  type        = string
}

variable "root_volume_size" {
  description = "ルート EBS のサイズ（GiB）。OS と Java のみを置く"
  type        = number
  default     = 8
}

variable "data_volume_size" {
  description = "ワールド用 EBS のサイズ（GiB）"
  type        = number
  default     = 8
}

variable "data_volume_final_snapshot" {
  description = "ワールド用 EBS を削除する前にスナップショットを取るか"
  type        = bool
  default     = true
}

variable "cpu_credits" {
  description = "T 系インスタンスの CPU クレジット（standard / unlimited）"
  type        = string
  default     = "unlimited"

  validation {
    condition     = contains(["standard", "unlimited"], var.cpu_credits)
    error_message = "cpu_credits は standard か unlimited を指定してください。"
  }
}

variable "use_eip" {
  description = "Elastic IP を割り当てるか。false の場合、起動するたびにパブリック IP が変わる"
  type        = bool
  default     = true
}

variable "minecraft_version" {
  description = "Minecraft サーバーのバージョン（例: 26.3）。latest は初回起動時点の最新リリース"
  type        = string
}

variable "accept_eula" {
  description = "Minecraft EULA（https://aka.ms/MinecraftEULA）に同意する場合のみ true。false ならサーバーは起動しない"
  type        = bool
  default     = false
}

variable "minecraft_port" {
  description = "Minecraft サーバーの待ち受けポート"
  type        = number
  default     = 25565
}

variable "jvm_memory_mb" {
  description = "/mc/ram が読めない場合に使う JVM ヒープサイズ（MB）。メモリ超過のチェックにも使う"
  type        = number
}

variable "os_reserved_memory_mb" {
  description = "JVM ヒープ以外（OS、JVM のネイティブ領域）に残すメモリ（MB）"
  type        = number
  default     = 512
}

variable "ram_parameter_name" {
  description = "JVM ヒープサイズを持つ SSM パラメータ名"
  type        = string
}

variable "shutdown_timer_seconds" {
  description = "/mc/shutdowntimer が読めない場合に使う自動停止までの秒数"
  type        = number
}

variable "shutdown_timer_parameter_name" {
  description = "自動停止までの秒数を持つ SSM パラメータ名"
  type        = string
}

variable "ops_parameter_name" {
  description = "op を付けるプレイヤー名を持つ SecureString パラメータ名"
  type        = string
}

variable "whitelist_parameter_name" {
  description = "ホワイトリストに入れるプレイヤー名を持つ SecureString パラメータ名"
  type        = string
}

variable "secure_parameter_dummy_value" {
  description = "SecureString パラメータが未設定であることを表す値"
  type        = string
  default     = "dummy"
}

variable "backup_s3_uri" {
  description = "バックアップの保存先（s3://bucket/prefix）。null ならバックアップしない"
  type        = string
  default     = null
}

variable "backup_on_calendar" {
  description = "日次バックアップの systemd OnCalendar 式（インスタンスの時刻は UTC）"
  type        = string
  default     = "*-*-* 18:00:00"
}
