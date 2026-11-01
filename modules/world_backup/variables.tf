variable "bucket_name" {
  description = "バックアップ・配布バケット名。非公開設定から渡す。"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "S3 バケット名の規則（英小文字・数字・ハイフン、3〜63 文字）に合わせてください。"
  }
}

variable "log_bucket_name" {
  description = "bootstrap で作成したサーバーアクセスログの配信先バケット名。"
  type        = string
  sensitive   = true
}

variable "noncurrent_version_days" {
  description = "上書き・削除されたオブジェクトの旧版を残す日数。"
  type        = number
  default     = 7

  validation {
    condition     = var.noncurrent_version_days >= 1 && var.noncurrent_version_days <= 30
    error_message = "旧版の保存日数は 1〜30 日にしてください。"
  }
}
