# Get secrets
data "aws_secretsmanager_secret" "jwt_keys" {
  name = "/backend/server/jwt/pair"
}

data "aws_secretsmanager_secret" "app_store_in_app_purchase_key" {
  name = "/backend/server/in-app-purchase-key"
}

data "aws_secretsmanager_secret" "apple_sign_in_private_key" {
  name = "/backend/server/apple-sign-in-private-key"
}

# Get the latest ECS-optimized AMI (Amazon Linux 2023)
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-ecs-hvm-2023*-x86_64"]
  }
}
