variable "name_prefix" {
  description = "リソース名の接頭辞"
  type        = string
}

variable "vpc_id" {
  description = "セキュリティグループを作成する VPC の ID"
  type        = string
}

variable "minecraft_port" {
  description = "Minecraft サーバーの待ち受けポート"
  type        = number
  default     = 25565
}

variable "minecraft_ingress_cidrs" {
  description = "Minecraft ポートへの接続を許可する CIDR"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_ingress_cidrs" {
  description = "SSH（22/TCP）を許可する CIDR。EC2 Instance Connect の CIDR を想定。空なら SSH を開けない"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.ssh_ingress_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "ssh_ingress_cidrs には 0.0.0.0/0 以外の有効な IPv4 CIDR を指定してください。"
  }
}
