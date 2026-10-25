output "vpc_id" {
  description = "VPC ID"
  value       = local.vpc_id
}

output "subnet_id" {
  description = "インスタンスを配置するパブリックサブネットの ID"
  value       = local.subnet_id
}
