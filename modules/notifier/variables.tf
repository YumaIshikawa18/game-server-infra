variable "prefix" {
  description = "非公開設定から渡すリソース名の接頭辞。"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "AWS リージョン。"
  type        = string
  default     = "ap-northeast-1"
}

variable "notification_email" {
  description = "warn / error の通知を受けるメールアドレス。非公開設定から渡す。"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.notification_email))
    error_message = "メールアドレスの形式で指定してください。"
  }
}

variable "webhook_parameter_name" {
  description = "Discord の Webhook URL を本人が登録する SSM SecureString の名前。"
  type        = string
  sensitive   = true

  validation {
    condition     = startswith(var.webhook_parameter_name, "/")
    error_message = "SSM パラメータ名は / で始めてください。"
  }
}

variable "permissions_boundary_arn" {
  description = "bootstrap で作成した app ロール用の permissions boundary。"
  type        = string
  sensitive   = true
}

variable "source_dir" {
  description = "notifier.py のあるディレクトリ。"
  type        = string
}

variable "build_dir" {
  description = "zip の出力先（gitignore 済み）。"
  type        = string
}

variable "log_retention_days" {
  description = "Lambda のログの保存日数。"
  type        = number
  default     = 14
}
