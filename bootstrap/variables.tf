variable "region" {
  description = "AWS リージョン（envs/prod と揃えること）"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "プロジェクト名（envs/prod の project_name と揃えること）"
  type        = string
  default     = "minecraft"
}

variable "environment" {
  description = "デプロイ先の環境名。GitHub Environment 名と envs/<environment> に対応する"
  type        = string
  default     = "prod"
}

variable "ops_environment" {
  description = "server-control ワークフローが使う GitHub Environment 名（承認なしで使う想定）"
  type        = string
  default     = "prod-ops"
}

variable "github_owner" {
  description = "GitHub リポジトリのオーナー（ユーザー名または Organization 名）"
  type        = string
}

variable "github_repository" {
  description = "GitHub リポジトリ名"
  type        = string
}

variable "github_default_branch" {
  description = "CD を実行するブランチ"
  type        = string
  default     = "master"
}

variable "create_github_oidc_provider" {
  description = "GitHub Actions の OIDC プロバイダを作成するか。アカウントに既にある場合は false"
  type        = bool
  default     = true
}

variable "ssm_parameter_prefix" {
  description = "Minecraft 用 SSM パラメータの接頭辞（envs/prod と揃えること）"
  type        = string
  default     = "/mc"
}

variable "state_bucket_name" {
  description = "tfstate 用 S3 バケット名。null なら <project>-tfstate-<account_id>-<region>"
  type        = string
  default     = null
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
