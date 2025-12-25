# Get secrets
data "aws_secretsmanager_secret" "jwt_keys" {
  name = "server/jwt"
}
data "aws_secretsmanager_secret_version" "jwt_keys_version" {
  secret_id = data.aws_secretsmanager_secret.jwt_keys.id
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
