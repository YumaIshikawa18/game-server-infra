variable "name_prefix" {
  description = "リソース名の接頭辞"
  type        = string
}

variable "instance_role_name" {
  description = "アップロード権限を付与するインスタンスロール名"
  type        = string
}

variable "object_prefix" {
  description = "バックアップを置くオブジェクトキーの接頭辞"
  type        = string
  default     = "backups"
}

variable "retention_days" {
  description = "バックアップの保持日数"
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days >= 1
    error_message = "retention_days は 1 以上を指定してください。"
  }
}

variable "force_destroy" {
  description = "true の場合、オブジェクトが残っていてもバケットを削除できる"
  type        = bool
  default     = false
}
