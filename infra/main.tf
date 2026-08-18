terraform {
  required_version = ">= 1.11.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.51"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.3"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }

  backend "s3" {
    bucket         = "bochi-state-w6jc0hxx7cnmrwqd"
    key            = "terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "bochi-state-lock-gdsebtzdtwdngb3e"
  }
}

provider "aws" {
  region = "eu-west-2"
}

provider "cloudflare" {}

locals {
  domain_name                = "bochi.app"
  apple_sign_in_team_id      = "4424D9K858"
  apple_sign_in_key_id       = "7R896F67DD"
  app_store_server_issuer_id = "b5247a42-eb15-4b45-b327-4646244f8778"
  app_store_server_key_id    = "AYQPQGTG88"
  app_store_server_bundle_id = "app.bochi"
}

moved {
  from = aws_ecr_repository.bochi_backend_server
  to   = aws_ecr_repository.bochi_server
}

resource "aws_s3_bucket" "state_bucket" {
  bucket = "bochi-state-w6jc0hxx7cnmrwqd"
}

resource "aws_dynamodb_table" "state_lock" {
  name         = "bochi-state-lock-gdsebtzdtwdngb3e"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

resource "aws_ecr_repository" "bochi_server" {
  name = "bochi-backend-server"
  # We want to mutate the "latest" tag
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "bochi_migration_runner" {
  name                 = "bochi-migration-runner"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}


resource "aws_ecs_cluster" "bochi" {
  name = "bochi_cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

module "database" {
  source              = "./services/database"
  vpc_id              = aws_vpc.bochi.id
  private_subnet_id   = aws_subnet.private_a.id
  private_subnet_b_id = aws_subnet.private_b.id
}

module "ci" {
  source = "./services/ci"
  container_registry_arn_list = [
    aws_ecr_repository.bochi_server.arn,
    aws_ecr_repository.bochi_migration_runner.arn
  ]
  ecs_cluster_name           = aws_ecs_cluster.bochi.name
  server_service_name        = "bochi-server"
  vpc_id                     = aws_vpc.bochi.id
  private_subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  database_security_group_id = module.database.database_security_group_id
  migration_repository_url   = aws_ecr_repository.bochi_migration_runner.repository_url
  database_secret_arn        = module.database.database_secret_arn
  database_kms_key_arn       = module.database.database_kms_key_arn
  database_endpoint          = module.database.database_endpoint
}

module "server" {
  source = "./services/server"

  vpc_id                     = aws_vpc.bochi.id
  private_subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  ecs_cluster_id             = aws_ecs_cluster.bochi.id
  ecs_cluster_name           = aws_ecs_cluster.bochi.name
  database_security_group_id = module.database.database_security_group_id
  database_secret_arn        = module.database.database_secret_arn
  database_kms_key_arn       = module.database.database_kms_key_arn
  database_endpoint          = module.database.database_endpoint
  apple_sign_in_team_id      = local.apple_sign_in_team_id
  apple_sign_in_key_id       = local.apple_sign_in_key_id
  app_store_server_issuer_id = local.app_store_server_issuer_id
  app_store_server_key_id    = local.app_store_server_key_id
  app_store_server_bundle_id = local.app_store_server_bundle_id
  ecr_repository_url         = aws_ecr_repository.bochi_server.repository_url
  alb_security_group_id      = aws_security_group.alb.id
  https_listener_arn         = aws_lb_listener.https.arn
}
