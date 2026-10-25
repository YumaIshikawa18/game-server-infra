resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-server"
  description = "Minecraft Java server"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-server" }

  lifecycle {
    create_before_destroy = true
  }
}

#trivy:ignore:AWS-0107 プレイヤー接続用のポートは意図的にインターネットへ公開する
resource "aws_vpc_security_group_ingress_rule" "minecraft" {
  for_each = toset(var.minecraft_ingress_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "Minecraft Java players"
  ip_protocol       = "tcp"
  from_port         = var.minecraft_port
  to_port           = var.minecraft_port
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_ingress_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "SSH from EC2 Instance Connect"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

# dnf / Mojang からのダウンロード、SSM、S3 への通信に必要
#trivy:ignore:AWS-0104 NAT やエンドポイントを持たない構成のため外向き通信は全許可
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
