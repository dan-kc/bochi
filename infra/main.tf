terraform {
  required_version = ">= 1.10.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
  }

  backend "s3" {
    bucket         = "tofustash-terraform-state-w6jc0hxx7cnmrwqd"
    key            = "terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "tofustash-terraform-state-lock-gdsebtzdtwdngb3e"
  }
}

provider "aws" {
  region = "eu-west-2"
}

resource "aws_s3_bucket" "terraform_state_bucket" {
  bucket = "tofustash-terraform-state-w6jc0hxx7cnmrwqd"
}

resource "aws_dynamodb_table" "terraform_state_lock" {
  name         = "tofustash-terraform-state-lock-gdsebtzdtwdngb3e"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ECR repo for server
resource "aws_ecr_repository" "tofustash_backend" {
  name                 = "tofustash-backend"
  image_tag_mutability = "MUTABLE" # Because we want to update "Latest"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ECR repo for flyway image.
resource "aws_ecr_repository" "tofustash_migration" {
  name                 = "tofustash-migration"
  image_tag_mutability = "MUTABLE" # Because we want to update "Latest"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "tofustash" {
  name = "tofustash_cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

module "database" {
  source              = "./services/database"
  vpc_id              = aws_vpc.tofustash.id
  private_subnet_id   = aws_subnet.private.id
  private_subnet_b_id = aws_subnet.private_b.id
  private_subnet_cidr = aws_subnet.private.cidr_block
}

module "ci" {
  source = "./services/ci"
  container_registry_arn_list = [
    aws_ecr_repository.tofustash_backend.arn,
    aws_ecr_repository.tofustash_migration.arn
  ]
  ecs_cluster_id             = aws_ecs_cluster.tofustash.id
  vpc_id                     = aws_vpc.tofustash.id
  private_subnet_ids         = [aws_subnet.private.id, aws_subnet.private_b.id]
  database_security_group_id = module.database.database_security_group_id
  migration_repository_url   = aws_ecr_repository.tofustash_migration.repository_url
  database_secret_arn        = module.database.database_secret_arn
  database_kms_key_arn       = module.database.database_kms_key_arn
}

# module "server" {
#   source = "./services/server"
#
#   vpc_id                     = aws_vpc.tofustash.id
#   private_subnet_ids         = [aws_subnet.private.id, aws_subnet.private_b.id]
#   ecs_cluster_id             = aws_ecs_cluster.tofustash.id
#   ecs_cluster_name           = aws_ecs_cluster.tofustash.name
#   database_security_group_id = module.database.database_security_group_id
#   database_secret_arn        = module.database.database_secret_arn
#   database_kms_key_arn       = module.database.database_kms_key_arn
#   database_endpoint          = module.database.database_endpoint
#   ecr_repository_url         = aws_ecr_repository.tofustash_backend.repository_url
#   alb_security_group_id      = aws_security_group.alb.id
#   https_listener_arn         = aws_lb_listener.https.arn
# }
