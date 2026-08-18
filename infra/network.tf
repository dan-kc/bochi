resource "aws_vpc" "bochi" {
  cidr_block           = "134.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.bochi.id
  cidr_block        = "134.0.1.0/24"
  availability_zone = "eu-west-2a"
  tags = {
    Name = "bochi-private-subnet-a"
  }
}

# Additional private subnet for RDS subnet group (required minimum 2 subnets)
# and for canary deploys
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.bochi.id
  cidr_block        = "134.0.2.0/24"
  availability_zone = "eu-west-2b"
  tags = {
    Name = "bochi-private-subnet-b"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.bochi.id
  cidr_block              = "134.0.3.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "bochi-public-subnet-a"
  }
}

# Additional public subnet for ALB (requires 2 AZs)
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.bochi.id
  cidr_block              = "134.0.4.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "bochi-public-subnet-b"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.bochi.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.bochi.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  tags = {
    Name = "bochi-nat-gateway"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.bochi.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
