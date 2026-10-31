variable "prefix" {
  description = "非公開設定から渡すリソース名の接頭辞。"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.prefix))
    error_message = "prefix は小文字で始まる 3〜24 文字の英小文字・数字・ハイフンにしてください。"
  }
}

variable "vpc_cidr" {
  description = "専用 VPC の IPv4 CIDR。"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && try(tonumber(split("/", var.vpc_cidr)[1]) == 24, false)
    error_message = "IPv4 /24 の CIDR を指定してください。"
  }
}

variable "availability_zone" {
  description = "対象インスタンスタイプに対応する東京の AZ。実アカウントで確認して渡す。"
  type        = string

  validation {
    condition     = can(regex("^ap-northeast-1[a-z]$", var.availability_zone))
    error_message = "東京リージョンの AZ を指定してください。"
  }
}
