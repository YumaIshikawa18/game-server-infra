locals {
  vpc_id    = var.use_default_vpc ? data.aws_vpc.default[0].id : aws_vpc.this[0].id
  subnet_id = var.use_default_vpc ? data.aws_subnet.default[0].id : aws_subnet.public[0].id
}

################################################################################
# 既定 VPC を使う場合
################################################################################

data "aws_vpc" "default" {
  count = var.use_default_vpc ? 1 : 0

  default = true
}

data "aws_subnet" "default" {
  count = var.use_default_vpc ? 1 : 0

  vpc_id            = data.aws_vpc.default[0].id
  availability_zone = var.availability_zone
  default_for_az    = true
}

################################################################################
# 専用 VPC を作る場合
################################################################################

#trivy:ignore:AWS-0178 フローログは 1 インスタンス構成では費用対効果が低いため無効
resource "aws_vpc" "this" {
  count = var.use_default_vpc ? 0 : 1

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "this" {
  count = var.use_default_vpc ? 0 : 1

  vpc_id = aws_vpc.this[0].id

  tags = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count = var.use_default_vpc ? 0 : 1

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zone
  # パブリック IP はインスタンス側（associate_public_ip_address）で明示的に付与する
  map_public_ip_on_launch = false

  tags = { Name = "${var.name_prefix}-public-${var.availability_zone}" }
}

resource "aws_route_table" "public" {
  count = var.use_default_vpc ? 0 : 1

  vpc_id = aws_vpc.this[0].id

  tags = { Name = "${var.name_prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  count = var.use_default_vpc ? 0 : 1

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count = var.use_default_vpc ? 0 : 1

  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}
