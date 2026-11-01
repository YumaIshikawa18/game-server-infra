variable "prefix" {
  description = "非公開設定から渡すリソース名の接頭辞。管理対象インスタンスの Project タグにも使う。"
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

variable "events_topic_arn" {
  description = "強制停止を通知する events トピック。"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", var.events_topic_arn))
    error_message = "SNS トピックの ARN を指定してください。"
  }
}

variable "permissions_boundary_arn" {
  description = "bootstrap で作成した app ロール用の permissions boundary。"
  type        = string
  sensitive   = true
}

variable "source_dir" {
  description = "watchdog.py のあるディレクトリ。"
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
