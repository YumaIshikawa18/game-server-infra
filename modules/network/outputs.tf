output "vpc_id" {
  description = "専用 VPC の識別子。"
  value       = aws_vpc.minecraft.id
  sensitive   = true
}

output "subnet_id" {
  description = "公開サブネットの識別子。"
  value       = aws_subnet.public.id
  sensitive   = true
}

output "security_group_id" {
  description = "Minecraft 専用 SG の識別子。"
  value       = aws_security_group.minecraft.id
  sensitive   = true
}
