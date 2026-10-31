resource "aws_vpc" "minecraft" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.prefix}-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.minecraft.id
  cidr_block              = var.vpc_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.prefix}-public"
  }
}

resource "aws_internet_gateway" "minecraft" {
  vpc_id = aws_vpc.minecraft.id

  tags = {
    Name = "${var.prefix}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.minecraft.id

  tags = {
    Name = "${var.prefix}-public"
  }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.minecraft.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "minecraft" {
  # CKV2_AWS_5: ENI への関連付けは呼び出し元の minecraft_server モジュールで行う。
  name        = "${var.prefix}-minecraft"
  description = "Minecraft Java access; administration uses SSM"
  vpc_id      = aws_vpc.minecraft.id

  tags = {
    Name = "${var.prefix}-minecraft"
  }
}

resource "aws_vpc_security_group_ingress_rule" "minecraft" {
  security_group_id = aws_security_group.minecraft.id
  description       = "Minecraft Java with authenticated account and whitelist"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 25565
  to_port           = 25565
}

resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.minecraft.id
  description       = "Downloads, SSM, metrics and backup service access"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
