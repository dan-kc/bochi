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
    Name = "tofustash-private-a"
  }
}

# Additional private subnet for RDS subnet group (required minimum 2 subnets)
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.tofustash.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "eu-west-2b"
  tags = {
    Name = "tofustash-private-b"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.tofustash.id
  cidr_block              = "10.1.3.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "tofustash-public-a"
  }
}

# Additional public subnet for ALB (requires 2 AZs)
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.tofustash.id
  cidr_block              = "10.1.4.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "tofustash-public-a"
  }
}


# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.tofustash.id
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.tofustash.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Route table for private subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.tofustash.id

  # No default route - private subnets have no internet access
  # AWS services are accessed via VPC endpoints
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "tofustash-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.tofustash.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.tofustash.cidr_block]
    description = "HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# VPC Endpoint for Secrets Manager
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.tofustash.id
  service_name        = "com.amazonaws.eu-west-2.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

# VPC Endpoint for ECR API
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.tofustash.id
  service_name        = "com.amazonaws.eu-west-2.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

# VPC Endpoint for ECR Docker Registry
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.tofustash.id
  service_name        = "com.amazonaws.eu-west-2.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

# VPC Endpoint for CloudWatch Logs
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.tofustash.id
  service_name        = "com.amazonaws.eu-west-2.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

# VPC Endpoint for S3 (Gateway endpoint - required for ECR image layers)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.tofustash.id
  service_name      = "com.amazonaws.eu-west-2.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}

# VPC Endpoint for ECS
resource "aws_vpc_endpoint" "ecs" {
  vpc_id              = aws_vpc.tofustash.id
  service_name        = "com.amazonaws.eu-west-2.ecs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

# VPC Endpoint for ECS Agent
resource "aws_vpc_endpoint" "ecs_agent" {
  vpc_id              = aws_vpc.tofustash.id
  service_name        = "com.amazonaws.eu-west-2.ecs-agent"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

# VPC Endpoint for ECS Telemetry
resource "aws_vpc_endpoint" "ecs_telemetry" {
  vpc_id              = aws_vpc.tofustash.id
  service_name        = "com.amazonaws.eu-west-2.ecs-telemetry"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}
