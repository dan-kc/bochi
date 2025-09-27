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

# Unique per AWS account. Already defined in keone.dev.
data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

# define an IAM Role in AWS that trusts this OIDC provider and grants the necessary permissions.
resource "aws_iam_role" "github_actions_ecr_uploader" {
  name = "github-actions-ecr-uploader"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com",
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" : "repo:dan-kc/habit-market-backend:*"
          }
        }
      }
    ]
  })
}

# Policy to interact with ECR
resource "aws_iam_policy" "ecr_upload_policy" {
  name        = "github-actions-ecr-upload-policy"
  description = "Allows GitHub Actions to push images to ECR"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken" # This specific action requires "*" resource
        ],
        Resource = "*" # MUST be "*" for GetAuthorizationToken
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
        ],
        Resource = [
          aws_ecr_repository.habit_market_backend.arn,
          aws_ecr_repository.habit_market_migration.arn
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_upload_policy_attachment" {
  role       = aws_iam_role.github_actions_ecr_uploader.name
  policy_arn = aws_iam_policy.ecr_upload_policy.arn
}
