output "instance_id" {
  description = "Minecraft の EC2。deploy.yml のスモークテストだけが内部で使う。"
  value       = aws_instance.minecraft.id
  sensitive   = true
}

output "public_ip" {
  description = "接続先の Elastic IP。公開ログには出さない。"
  value       = aws_eip.minecraft.public_ip
  sensitive   = true
}

output "role_name" {
  description = "ホスト用 IAM ロール名。"
  value       = aws_iam_role.server.name
  sensitive   = true
}

output "parameter_prefix" {
  description = "本人が whitelist を登録する SSM パラメータの接頭辞（<prefix>/whitelist）。"
  value       = local.param_prefix
  sensitive   = true
}
