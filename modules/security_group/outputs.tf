output "security_group_id" {
  description = "Minecraft サーバー用セキュリティグループの ID"
  value       = aws_security_group.this.id
}
