resource "aws_db_subnet_group" "habit_market" {
  name = "habit-market-db-subnet-group"

  # The second subnet in eu-west-2b is essentially unused - it's 
  # just there to satisfy AWS's requirement. The database will
  # only ever run in eu-west-2a unless you manually change it or 
  # upgrade to Multi-AZ later.
  subnet_ids = [var.private_subnet_id, var.private_subnet_b_id]

  tags = {
    Name = "Habit Market DB subnet group"
  }
}

resource "aws_security_group" "database" {
  name        = "habit-market-database-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
    description = "Allow PostgreSQL from private subnet"
  }

  tags = {
    Name = "habit-market-database-sg"
  }
}

resource "aws_db_instance" "habit_market" {
  identifier     = "habit-market"
  engine         = "postgres"
  engine_version = "17.6"

  # Cost-optimized instance settings
  instance_class    = "db.t3.micro" # Cheapest instance type
  allocated_storage = 20            # Minimum storage
  storage_type      = "gp2"         # General purpose SSD
  storage_encrypted = true

  # Database configuration
  db_name = "habit_market"
  port    = 5432

  # Credentials managed by Secrets Manager
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.database.id
  username                      = "postgres"

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.habit_market.name
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

  tags = {
    Name        = "habit-market-database"
    Environment = "production"
  }
}

# KMS key for Secrets Manager encryption
resource "aws_kms_key" "database" {
  description             = "KMS key for RDS Secrets Manager"
  deletion_window_in_days = 10

  tags = {
    Name = "habit-market-database-kms"
  }
}

resource "aws_kms_alias" "database" {
  name          = "alias/habit-market-database"
  target_key_id = aws_kms_key.database.key_id
}

output "database_endpoint" {
  value       = aws_db_instance.habit_market.endpoint
  description = "Database connection endpoint"
}
