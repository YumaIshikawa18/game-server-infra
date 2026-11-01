# 値はすべて非公開設定から渡す（CI: TF_INPUTS_JSON、手元: gitignore 済みの *.auto.tfvars）。
variable "allowed_account_ids" {
  description = "デプロイ先として許可するアカウント。"
  type        = list(string)
  sensitive   = true
}

variable "prefix" {
  description = "bootstrap と同じ、リソース名の非公開の接頭辞。"
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

  validation {
    condition     = var.region == "ap-northeast-1"
    error_message = "本番は東京リージョン（ap-northeast-1）だけです。"
  }
}

variable "availability_zone" {
  description = "サブネットとワールド EBS の AZ。m7g.xlarge が使えることを確認済みの AZ にする。"
  type        = string
  default     = "ap-northeast-1a"
}

variable "backup_bucket_name" {
  description = "バックアップ・配布バケット名。"
  type        = string
  sensitive   = true
}

variable "log_bucket_name" {
  description = "bootstrap のアクセスログ・フローログ用バケット名。"
  type        = string
  sensitive   = true
}

variable "notification_email" {
  description = "warn / error の通知を受けるメールアドレス。"
  type        = string
  sensitive   = true
}

variable "monthly_budget_usd" {
  description = "月 3,000 円相当の予算（USD）。"
  type        = number
}

variable "accept_minecraft_eula" {
  description = "Minecraft の EULA（https://aka.ms/MinecraftEULA）に同意したことを本人が示す。"
  type        = bool
}
