resource "aws_vpc" "tofustash" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.tofustash.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "eu-west-2a"
  tags = {
    Name = "tofustash-private-subnet-a"
  }
}

# Additional private subnet for RDS subnet group (required minimum 2 subnets)
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.tofustash.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "eu-west-2b"
  tags = {
    Name = "tofustash-private-subnet-b"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.tofustash.id
  cidr_block              = "10.1.3.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "tofustash-public-subnet-a"
  }
}

# Additional public subnet for ALB (requires 2 AZs)
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.tofustash.id
  cidr_block              = "10.1.4.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "tofustash-public-subnet-b"
  }
}


# # Internet Gateway
# resource "aws_internet_gateway" "main" {
#   vpc_id = aws_vpc.tofustash.id
# }
#
# # Route table for public subnets
# resource "aws_route_table" "public" {
#   vpc_id = aws_vpc.tofustash.id
#
#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.main.id
#   }
# }
#
# resource "aws_route_table_association" "public_a" {
#   subnet_id      = aws_subnet.public.id
#   route_table_id = aws_route_table.public.id
# }
#
# resource "aws_route_table_association" "public_b" {
#   subnet_id      = aws_subnet.public_b.id
#   route_table_id = aws_route_table.public.id
# }
#
# # Elastic IP for NAT Gateway
# resource "aws_eip" "nat" {
#   domain = "vpc"
#   tags = {
#     Name = "tofustash-nat-eip"
#   }
# }
#
# # NAT Gateway in public subnet
# resource "aws_nat_gateway" "main" {
#   allocation_id = aws_eip.nat.id
#   subnet_id     = aws_subnet.public.id
#   tags = {
#     Name = "tofustash-nat-gateway"
#   }
# }
#
# # Route table for private subnets
# resource "aws_route_table" "private" {
#   vpc_id = aws_vpc.tofustash.id
#
#   route {
#     cidr_block     = "0.0.0.0/0"
#     nat_gateway_id = aws_nat_gateway.main.id
#   }
# }
#
# resource "aws_route_table_association" "private" {
#   subnet_id      = aws_subnet.private.id
#   route_table_id = aws_route_table.private.id
# }
#
# resource "aws_route_table_association" "private_b" {
#   subnet_id      = aws_subnet.private_b.id
#   route_table_id = aws_route_table.private.id
# }
#
# # VPC Endpoint for S3
# resource "aws_vpc_endpoint" "s3" {
#   vpc_id            = aws_vpc.tofustash.id
#   service_name      = "com.amazonaws.eu-west-2.s3"
#   vpc_endpoint_type = "Gateway"
#   route_table_ids   = [aws_route_table.private.id]
# }
