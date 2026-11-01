variable "prefix" {
  description = "非公開設定から渡すリソース名の接頭辞。"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.prefix))
    error_message = "prefix は小文字で始まる 3〜24 文字の英小文字・数字・ハイフンにしてください。"
  }
}

variable "region" {
  description = "AWS リージョン。"
  type        = string
  default     = "ap-northeast-1"
}

variable "subnet_id" {
  description = "公開サブネット。"
  type        = string
  sensitive   = true
}

variable "availability_zone" {
  description = "サブネットと同じ AZ。ワールド EBS もここに作る。"
  type        = string
}

variable "security_group_id" {
  description = "25565/TCP だけを許可する SG。"
  type        = string
  sensitive   = true
}

variable "backup_bucket_name" {
  description = "バックアップ・配布バケット名。"
  type        = string
  sensitive   = true
}

variable "events_topic_arn" {
  description = "ホストのスクリプトが通知を送る SNS の events トピック。"
  type        = string
  sensitive   = true
}

variable "permissions_boundary_arn" {
  description = "bootstrap で作成した app ロール用の permissions boundary。"
  type        = string
  sensitive   = true
}

variable "log_retention_days" {
  description = "サーバーとスクリプトのログの保存日数（プレイヤー名を含むため短くする）。"
  type        = number
  default     = 14
}

variable "cpu_architecture" {
  description = "EC2 の CPU アーキテクチャ。"
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.cpu_architecture)
    error_message = "cpu_architecture は arm64 か x86_64 にしてください。"
  }
}

variable "instance_type" {
  description = "EC2 のインスタンスタイプ。cpu_architecture ごとの許可リストから選ぶ。"
  type        = string
  default     = "m7g.xlarge"

  validation {
    condition     = contains(local.allowed_instance_types[var.cpu_architecture], var.instance_type)
    error_message = "instance_type が cpu_architecture の許可リストにありません。"
  }
}

variable "root_volume_size" {
  description = "ルート EBS（GB）。"
  type        = number
  default     = 8
}

variable "world_volume_size" {
  description = "ワールド用 EBS（GB）。縮小はできない。"
  type        = number
  default     = 30

  validation {
    condition     = var.world_volume_size >= 10 && var.world_volume_size <= 200
    error_message = "ワールド用 EBS は 10〜200 GB にしてください。"
  }
}

variable "accept_minecraft_eula" {
  description = "Minecraft の EULA（https://aka.ms/MinecraftEULA）に同意したことを示す。本人が非公開設定で true にする。"
  type        = bool

  validation {
    condition     = var.accept_minecraft_eula
    error_message = "Minecraft サーバーの実行には EULA への同意が必要です。内容を確認し、非公開設定で true にしてください。"
  }
}

variable "minecraft_version" {
  description = "Minecraft のバージョン。latest などの実行時に決まる値は使わない（FR2.1）。"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.minecraft_version))
    error_message = "Minecraft のバージョンは 26.3 や 1.21.11 のような具体値にしてください。"
  }
}

variable "loader" {
  description = "MOD ローダー（FR2.2）。"
  type        = string
  default     = "vanilla"

  validation {
    condition     = contains(["vanilla", "forge", "neoforge", "fabric"], var.loader)
    error_message = "loader は vanilla / forge / neoforge / fabric のいずれかにしてください。"
  }
}

variable "loader_version" {
  description = "ローダーのバージョン。vanilla 以外では具体値が必須。"
  type        = string
  default     = null

  validation {
    condition = (
      var.loader == "vanilla" ? var.loader_version == null :
      can(regex("^[0-9][0-9A-Za-z.+-]*$", coalesce(var.loader_version, "-")))
    )
    error_message = "vanilla では loader_version を指定せず、それ以外では latest などではない具体値を指定してください。"
  }
}

variable "mods" {
  description = "MOD 一覧。sha256 を照合してから配置する。side=client の MOD はサーバーに置かない。"
  type = list(object({
    name   = string
    url    = string
    sha256 = string
    side   = string
  }))
  default = []

  validation {
    condition = alltrue([for mod in var.mods :
      can(regex("^[A-Za-z0-9._-]{1,64}$", mod.name)) && startswith(mod.url, "https://")
      && can(regex("^[0-9a-f]{64}$", mod.sha256)) && contains(["server", "client", "both"], mod.side)
    ]) && length(distinct([for mod in var.mods : mod.name])) == length(var.mods)
    error_message = "MOD は重複しない名前、https の URL、64 桁の sha256、side（server / client / both）を指定してください。"
  }
  validation {
    condition     = var.loader != "vanilla" || length([for mod in var.mods : mod if mod.side != "client"]) == 0
    error_message = "vanilla ではサーバーに MOD を置けません。loader を指定してください。"
  }
}

variable "game_settings" {
  description = "server.properties 相当の設定。"
  type = object({
    max_players         = optional(number, 10)
    view_distance       = optional(number, 10)
    simulation_distance = optional(number, 8)
    difficulty          = optional(string, "normal")
    motd                = optional(string, "Minecraft")
  })
  default = {}

  validation {
    condition = (
      var.game_settings.max_players >= 1 && var.game_settings.max_players <= 20
      && var.game_settings.view_distance >= 4 && var.game_settings.view_distance <= 16
      && var.game_settings.simulation_distance >= 4 && var.game_settings.simulation_distance <= 12
      && contains(["peaceful", "easy", "normal", "hard"], var.game_settings.difficulty)
      && can(regex("^[ -~]{1,59}$", var.game_settings.motd))
    )
    error_message = "max_players は 1〜20、view_distance は 4〜16、simulation_distance は 4〜12、difficulty は peaceful / easy / normal / hard、motd は ASCII 59 文字以内にしてください。"
  }
}

variable "jvm_heap_override" {
  description = "JVM ヒープ上限（GB）。null ならインスタンスメモリの 75%。"
  type        = number
  default     = null
}

variable "compose_file" {
  description = "docker/compose.yml の内容（イメージは digest で固定）。"
  type        = string

  validation {
    condition     = can(regex("image: [^\\s]+@sha256:[0-9a-f]{64}", var.compose_file))
    error_message = "compose のイメージは digest（@sha256:...）で固定してください。"
  }
}

variable "docker_compose_plugin" {
  description = "ホストに入れる docker compose プラグインの版と、アーキテクチャごとの sha256。"
  type = object({
    version = string
    sha256  = map(string)
  })
  default = {
    version = "v5.6.1"
    sha256 = {
      arm64  = "42cfa75f51ad0ccf290bad37899e0038a8c10a0069e85233ecc1d53e3ff1347d"
      x86_64 = "47737f4236e6d3ccea7291995203f8f018058783b4c3a9469119811a0b5db8c0"
    }
  }
}
