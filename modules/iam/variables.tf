variable "name_prefix" {
  description = "リソース名の接頭辞"
  type        = string
}

variable "ssm_parameter_arns" {
  description = "インスタンスが読み取る SSM パラメータの ARN"
  type        = list(string)
}

variable "permissions_boundary_arn" {
  description = "インスタンスロールに付ける permissions boundary の ARN。null なら付けない"
  type        = string
  default     = null
}
