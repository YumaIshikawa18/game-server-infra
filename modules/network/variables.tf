variable "name_prefix" {
  description = "リソース名の接頭辞"
  type        = string
}

variable "use_default_vpc" {
  description = "true の場合は既定 VPC の既定サブネットを使い、false の場合は専用 VPC を作成する"
  type        = bool
  default     = false
}

variable "availability_zone" {
  description = "サブネットを配置する AZ。インスタンスタイプが提供されている AZ を指定すること"
  type        = string
}

variable "vpc_cidr" {
  description = "専用 VPC の CIDR（use_default_vpc = false のときのみ使用）"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr は有効な IPv4 CIDR を指定してください。"
  }
}

variable "public_subnet_cidr" {
  description = "パブリックサブネットの CIDR（use_default_vpc = false のときのみ使用）"
  type        = string
  default     = "10.0.0.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr は有効な IPv4 CIDR を指定してください。"
  }
}
