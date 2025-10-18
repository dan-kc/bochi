terraform {
  required_version = ">= 1.8.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.14"
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
  source = "./services/database"
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
}
