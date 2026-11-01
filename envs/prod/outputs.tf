# CI では terraform output を表示しない。deploy.yml は instance_id だけを内部で読む。
output "instance_id" {
  description = "Minecraft の EC2（apply 後のスモークテスト用）。"
  value       = module.minecraft_server.instance_id
  sensitive   = true
}

output "server_address" {
  description = "Minecraft クライアントの接続先（Elastic IP）。手元で確認し、公開しない。"
  value       = module.minecraft_server.public_ip
  sensitive   = true
}

output "whitelist_parameter" {
  description = "本人が whitelist を登録する SSM SecureString の名前。"
  value       = "${module.minecraft_server.parameter_prefix}/whitelist"
  sensitive   = true
}

output "discord_webhook_parameter" {
  description = "本人が Discord の Webhook URL を登録する SSM SecureString の名前。"
  value       = "/${var.prefix}/minecraft/discord-webhook"
  sensitive   = true
}
