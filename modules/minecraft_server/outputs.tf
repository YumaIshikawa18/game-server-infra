output "instance_id" {
  description = "EC2 インスタンス ID"
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "パブリック IP。use_eip = false の場合は起動のたびに変わる"
  value       = local.public_ip
}

output "server_address" {
  description = "Minecraft クライアントで指定する接続先"
  value       = "${local.public_ip}:${var.minecraft_port}"
}

output "data_volume_id" {
  description = "ワールド用 EBS のボリューム ID"
  value       = aws_ebs_volume.data.id
}

output "status_document_name" {
  description = "status 用 SSM ドキュメント名"
  value       = aws_ssm_document.status.name
}
