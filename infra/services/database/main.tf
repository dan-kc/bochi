variable "vpc_id" {
  type = string
}
variable "subnet_id" {
  type = string
}
variable "subnet_cidr" {
  type = string
}
variable "subnet_az" {
  type = string
}

# Security Group for Database
resource "aws_security_group" "database" {
  name        = "habit-market-database-sg"
  description = "Security group for PostgreSQL database"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.subnet_cidr]
  }
}


# EBS Volume for Data
resource "aws_ebs_volume" "database_data" {
  availability_zone = var.subnet_az
  size              = 16 # GB
  type              = "gp3"
  encrypted         = true
}

# Get latest Amazon Linux 2 ECS-optimized AMI
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Launch Template for EC2 Instance
# This is exclusively an EC2 concept.
resource "aws_launch_template" "ecs_instance" {
  name_prefix   = "habit-market-ecs-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t3.medium"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance.name
  }

  vpc_security_group_ids = [aws_security_group.database.id]

  # User data to join ECS cluster and mount EBS volume
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    cluster_name = aws_ecs_cluster.database.name
    volume_id    = aws_ebs_volume.database_data.id
  }))

  # Root volume
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 16
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "habit-market-ecs-database-instance"
    }
  }
}

# Auto Scaling Group (with min/max = 1 for single instance)
resource "aws_autoscaling_group" "ecs_instances" {
  name                = "habit-market-ecs-asg"
  vpc_zone_identifier = data.aws_subnets.default.ids
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1

  launch_template {
    id      = aws_launch_template.ecs_instance.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "habit-market-ecs-instance"
    propagate_at_launch = true
  }
}

# ECS Capacity Provider
# The managed_scaling block enables automatic scaling for this capacity 
# provider, aiming to maintain 100% target capacity utilization of the 
# Auto Scaling Group.
resource "aws_ecs_capacity_provider" "database" {
  name = "habit-market-database-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_instances.arn

    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "database" {
  cluster_name = aws_ecs_cluster.database.name

  capacity_providers = [aws_ecs_capacity_provider.database.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.database.name
  }
}

# IAM Role for ECS Task
resource "aws_iam_role" "ecs_task_execution" {
  name = "habit-market-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_secrets" {
  name = "habit-market-ecs-task-secrets-policy"
  role = aws_iam_role.ecs_task_execution.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "postgres" {
  name              = "/ecs/habit-market/postgres"
  retention_in_days = 7

  tags = {
    Name = "habit-market-postgres-logs"
  }
}

# ECS Task Definition for PostgreSQL
resource "aws_ecs_task_definition" "postgres" {
  family                   = "habit-market-postgres"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  volume {
    name      = "postgres-data"
    host_path = "/mnt/postgres-data"
  }

  container_definitions = jsonencode([
    {
      name  = "postgres"
      image = "postgres:18.0-alpine3.21"

      portMappings = [
        {
          containerPort = 5432
          hostPort      = 5432
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "POSTGRES_DB"
          value = "habit_market"
        },
        {
          name  = "PGDATA"
          value = "/var/lib/postgresql/data/pgdata"
        }
      ]

      secrets = [
        {
          name      = "POSTGRES_USER"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:username::"
        },
        {
          name      = "POSTGRES_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:password::"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "postgres-data"
          containerPath = "/var/lib/postgresql/data"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.postgres.name
          "awslogs-region"        = "eu-west-2"
          "awslogs-stream-prefix" = "postgres"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "pg_isready -U habitmarket"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      essential = true
    }
  ])

  tags = {
    Name = "habit-market-postgres-task"
  }
}

# ECS Service for PostgreSQL
resource "aws_ecs_service" "postgres" {
  name            = "habit-market-postgres-service"
  cluster         = aws_ecs_cluster.database.id
  task_definition = aws_ecs_task_definition.postgres.arn
  desired_count   = 1
  launch_type     = "EC2"

  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  placement_constraints {
    type = "distinctInstance"
  }

  tags = {
    Name = "habit-market-postgres-service"
  }
}

# Service Discovery Namespace
resource "aws_service_discovery_private_dns_namespace" "database" {
  name        = "habit-market.local"
  vpc         = data.aws_vpc.default.id
  description = "Private DNS namespace for habit-market database"

  tags = {
    Name = "habit-market-database-namespace"
  }
}

# Service Discovery Service
resource "aws_service_discovery_service" "postgres" {
  name = "postgres"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.database.id

    dns_records {
      ttl  = 60
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    # failure_threshold is deprecated and always set to 1 by AWS
  }
}

# Outputs
output "database_endpoint" {
  value       = "postgres.habit-market.local"
  description = "Internal DNS name for PostgreSQL database"
}

output "database_secret_arn" {
  value       = aws_secretsmanager_secret.db_credentials.arn
  description = "ARN of the secret containing database credentials"
}

output "ecs_cluster_name" {
  value       = aws_ecs_cluster.database.name
  description = "Name of the ECS cluster"
}

