locals {
  database_master_username         = "postgres"
  database_master_password_version = 1
}

resource "aws_db_subnet_group" "bochi" {
  name = "bochi-db-subnet-group"

  # RDS requires a DB subnet group to span at least two AZs,
  # even for a Single-AZ instance. With multi_az = false and
  # availability_zone pinned on the DB instance, the second subnet
  # is mainly there to satisfy the subnet group requirement and allow
  # future Multi-AZ migration.
  subnet_ids = [var.private_subnet_id, var.private_subnet_b_id]
}

resource "aws_security_group" "database" {
  name        = "bochi-database-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id
}

data "aws_secretsmanager_random_password" "database_master" {
  password_length = 48
  # RDS master passwords cannot contain /, ", @, or spaces.
  exclude_characters = "\"@/ "
}

resource "aws_db_instance" "bochi" {
  identifier     = "bochi"
  engine         = "postgres"
  engine_version = "17.9"

  # Cost-optimized instance settings
  instance_class    = "db.t3.micro" # Cheapest instance type
  allocated_storage = 20            # Minimum storage
  storage_type      = "gp2"         # General purpose SSD
  storage_encrypted = true

  # Database configuration
  db_name = "bochi"
  port    = 5432

  # Keep the password in our own secret so it does not rotate independently of
  # ECS tasks. ECS reads secret values only when a replacement task starts.
  username            = local.database_master_username
  password_wo         = data.aws_secretsmanager_random_password.database_master.random_password
  password_wo_version = local.database_master_password_version

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.bochi.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false

  # Single AZ for cost optimization
  multi_az          = false
  availability_zone = "eu-west-2a"

  # Backup settings - no automated backups for cost savings
  backup_retention_period = 0
  skip_final_snapshot     = true

  # Monitoring - regular CloudWatch logs only, no Performance Insights
  enabled_cloudwatch_logs_exports = ["postgresql"]
  performance_insights_enabled    = false
  monitoring_interval             = 0 # No enhanced monitoring

  # Maintenance and updates
  auto_minor_version_upgrade = true
  maintenance_window         = "sun:02:00-sun:03:00"

  # Additional settings for cost optimization
  deletion_protection = false
}

# KMS key for Secrets Manager encryption
resource "aws_kms_key" "database" {
  description             = "KMS key for RDS Secrets Manager"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "database" {
  name          = "alias/bochi-database"
  target_key_id = aws_kms_key.database.key_id
}

resource "aws_secretsmanager_secret" "database" {
  name       = "/bochi/database/master"
  kms_key_id = aws_kms_key.database.arn

  tags = {
    Name = "bochi-database-master-secret"
  }
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string_wo = jsonencode({
    username = local.database_master_username
    password = data.aws_secretsmanager_random_password.database_master.random_password
  })
  secret_string_wo_version = local.database_master_password_version
}

output "database_endpoint" {
  value       = aws_db_instance.bochi.endpoint
  description = "Database connection endpoint"
}

output "database_security_group_id" {
  value       = aws_security_group.database.id
  description = "Security group ID for the database"
}

output "database_secret_arn" {
  value       = aws_secretsmanager_secret.database.arn
  description = "ARN of the secret containing database credentials"
  depends_on  = [aws_secretsmanager_secret_version.database]
}

output "database_kms_key_arn" {
  value       = aws_kms_key.database.arn
  description = "ARN of the KMS key used to encrypt database secrets"
}
