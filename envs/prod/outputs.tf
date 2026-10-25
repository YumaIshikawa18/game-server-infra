output "instance_id" {
  description = "EC2 インスタンス ID"
  value       = module.minecraft_server.instance_id
}

output "public_ip" {
  description = "パブリック IP（use_eip = true なら Elastic IP）"
  value       = module.minecraft_server.public_ip
}

output "server_address" {
  description = "Minecraft クライアントの「サーバーアドレス」に入れる値"
  value       = module.minecraft_server.server_address
}

output "availability_zone" {
  description = "インスタンスを配置した AZ"
  value       = local.availability_zone
}

output "backup_bucket_name" {
  description = "バックアップ用 S3 バケット名（無効なら null）"
  value       = var.enable_backup ? module.world_backup[0].bucket_name : null
}
