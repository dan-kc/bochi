terraform {
  required_version = ">= 1.8.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.17"
    }
  }

  backend "s3" {
    bucket         = "habit-market-terraform-state-rcywkqjuwbvvfz9s3gam"
    key            = "terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "habit-market-terraform-state-lock-qayvqk9z2vtmh4frng2b"
  }
}

provider "aws" {
  region = "eu-west-2"
}

# Define ECR repo for server
resource "aws_ecr_repository" "habit_market_backend" {
  name                 = "habit-market-backend"
  image_tag_mutability = "MUTABLE" # Because we want to update "Latest"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Define ECR repo for flyway image.
resource "aws_ecr_repository" "habit_market_migration" {
  name                 = "habit-market-migration"
  image_tag_mutability = "MUTABLE" # Because we want to update "Latest"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "habit_market" {
  name = "habit_market_cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}


module "database" {
  source              = "./services/database"
  vpc_id              = aws_vpc.habit_market.id
  private_subnet_id   = aws_subnet.private.id
  private_subnet_b_id = aws_subnet.private_b.id
  private_subnet_cidr = aws_subnet.private.cidr_block
}

module "ci" {
  source = "./services/ci"
  container_registry_arn_list = [
    aws_ecr_repository.habit_market_backend.arn,
    aws_ecr_repository.habit_market_migration.arn
  ]
  ecs_cluster_id             = aws_ecs_cluster.habit_market.id
  vpc_id                     = aws_vpc.habit_market.id
  private_subnet_ids         = [aws_subnet.private.id, aws_subnet.private_b.id]
  database_security_group_id = module.database.database_security_group_id
  migration_repository_url   = aws_ecr_repository.habit_market_migration.repository_url
  database_secret_arn        = module.database.database_secret_arn
  database_kms_key_arn       = module.database.database_kms_key_arn
}

# Security group for Application Load Balancer
resource "aws_security_group" "alb" {
  name        = "habit-market-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.habit_market.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from anywhere"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "habit-market-alb-sg"
  }
}

# Application Load Balancer
# The ALB itself doesn't have a static IP address that you directly access. 
# Instead, AWS assigns a unique, stable DNS hostname to the ALB. 
resource "aws_lb" "habit_market" {
  name               = "habit-market-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public_b.id]

  enable_deletion_protection       = false
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "habit-market-alb"
  }
}

module "server" {
  source = "./services/server"

  vpc_id                     = aws_vpc.habit_market.id
  private_subnet_ids         = [aws_subnet.private.id, aws_subnet.private_b.id]
  ecs_cluster_id             = aws_ecs_cluster.habit_market.id
  ecs_cluster_name           = aws_ecs_cluster.habit_market.name
  database_security_group_id = module.database.database_security_group_id
  database_secret_arn        = module.database.database_secret_arn
  database_kms_key_arn       = module.database.database_kms_key_arn
  database_endpoint          = module.database.database_endpoint
  ecr_repository_url         = aws_ecr_repository.habit_market_backend.repository_url
  alb_arn                    = aws_lb.habit_market.arn
  alb_security_group_id      = aws_security_group.alb.id
}
