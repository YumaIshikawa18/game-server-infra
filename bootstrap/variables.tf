variable "allowed_account_ids" {
  description = "既存の非公開ローカル設定で指定するデプロイ先の許可アカウント。"
  type        = list(string)
  sensitive   = true
}

variable "prefix" {
  description = "すべての管理リソース名に使う非公開の接頭辞。"
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

variable "state_bucket_name" {
  description = "Terraform state と運用ロックの非公開バケット名。"
  type        = string
  sensitive   = true
}

variable "state_key" {
  description = "本番 Terraform state のオブジェクトキー。"
  type        = string
  default     = "prod/terraform.tfstate"
}

variable "lock_key" {
  description = "state と分離する運用ロックのオブジェクトキー。"
  type        = string
  default     = "control/operation.lock"

  validation {
    condition     = startswith(var.lock_key, "control/") && !endswith(var.lock_key, ".tflock")
    error_message = "運用ロックは control/ 配下とし Terraform のロックと分離してください。"
  }
}

variable "backup_bucket_name" {
  description = "本番のバックアップ・配布バケット名。IAM のアクセス対象に使用。"
  type        = string
  sensitive   = true
}

variable "log_bucket_name" {
  description = "state とバックアップのサーバーアクセスログを受ける非公開バケット名。"
  type        = string
  sensitive   = true
}

variable "access_log_retention_days" {
  description = "サーバーアクセスログの保存日数。"
  type        = number
  default     = 90

  validation {
    condition     = var.access_log_retention_days >= 1 && var.access_log_retention_days <= 365
    error_message = "保存日数は 1〜365 日にしてください。"
  }
}

variable "github_repository" {
  description = "OIDC trust を許可する owner/repository。非公開設定から渡す。"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "GitHub の owner/repository を指定してください。"
  }
}

variable "use_existing_github_oidc" {
  description = "既存の GitHub OIDC プロバイダーを変更せず再利用する。"
  type        = bool
  default     = true
}
