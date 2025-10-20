# ECS Task Definition
resource "aws_ecs_task_definition" "habit_market_server" {
  family                   = "habit-market-server" # "Name", basically
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "256" # 0.25 vCPU
  memory                   = "512" # 0.5 GB RAM
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "habit-market-server"
      image = "${var.ecr_repository_url}:latest"

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "RUST_LOG"
          value = "info"
        },
        {
          name  = "DB_NAME"
          value = "habit_market"
        },
        {
          name  = "DB_HOST"
          value = split(":", var.database_endpoint)[0]
        },
      ]

      secrets = [
        {
          name      = "DB_USER"
          valueFrom = "${var.database_secret_arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.database_secret_arn}:password::"
        },
        {
          name      = "JWT_PUBLIC_KEY"
          valueFrom = "${data.aws_secretsmanager_secret_version.jwt_keys_version.arn}:eddsa-public-key::"
        },
        {
          name      = "JWT_PRIVATE_KEY"
          valueFrom = "${data.aws_secretsmanager_secret_version.jwt_keys_version.arn}:eddsa-private-key::"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.habit_market_server.name
          "awslogs-region"        = "eu-west-2"
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true # If this container stops for any reason, the entire ECS task will stop.

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name = "habit-market-server-task-definition"
  }
}

# Security group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "habit-market-server-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
    description     = "Allow traffic from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "habit-market-server-ecs-tasks-sg"
  }
}

# Allow ECS tasks to connect to database
resource "aws_security_group_rule" "database_from_ecs" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_tasks.id
  security_group_id        = var.database_security_group_id
  description              = "Allow PostgreSQL from ECS tasks"
}

# CloudWatch log group for the application
resource "aws_cloudwatch_log_group" "habit_market_server" {
  name              = "/ecs/habit-market-server"
  retention_in_days = 7 # Keep logs for 7 days to save costs

  tags = {
    Name = "habit-market-server-logs"
  }
}

# Security group for EC2 instances
resource "aws_security_group" "ecs_instances" {
  name        = "habit-market-ecs-instances-sg"
  description = "Security group for ECS EC2 instances"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
    description     = "Allow all traffic from ALB" # Why do we allow all traffic? I should only allow 80 and 443 right?
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "habit-market-ecs-instances-sg"
  }
}

# Launch template for EC2 instances
resource "aws_launch_template" "ecs_instance" {
  name_prefix   = "habit-market-ecs-instance-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t3.micro"

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance_profile.arn
  }

  vpc_security_group_ids = [aws_security_group.ecs_instances.id]

  user_data = base64encode(<<-EOT
    #!/bin/bash
    echo ECS_CLUSTER=${var.ecs_cluster_name} >> /etc/ecs/ecs.config
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "habit-market-ecs-instance"
    }
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "ecs_instances" {
  name                = "habit-market-ecs-asg"
  vpc_zone_identifier = var.private_subnet_ids
  min_size            = 1
  max_size            = 2 # Allow scaling to 2 instances for canary deployments
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

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

# ECS Capacity Provider
resource "aws_ecs_capacity_provider" "ec2" {
  name = "habit-market-ec2-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_instances.arn

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 1
    }
  }
}

# Associate capacity provider with cluster
resource "aws_ecs_cluster_capacity_providers" "habit_market" {
  cluster_name = var.ecs_cluster_name

  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = 1
  }
}

# Blue Target Group for ALB
resource "aws_lb_target_group" "habit_market_server" {
  name        = "habit-market-server-tg-blue"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name = "habit-market-server-tg-blue"
  }
}

# Green Target Group for ALB
resource "aws_lb_target_group" "habit_market_server_green" {
  name        = "habit-market-server-tg-green"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name = "habit-market-server-tg-green"
  }
}

# CodeDeploy Application
resource "aws_codedeploy_app" "habit_market_server" {
  name             = "habit-market-server"
  compute_platform = "ECS"

  tags = {
    Name = "habit-market-server-codedeploy-app"
  }
}

# CodeDeploy Deployment Group
resource "aws_codedeploy_deployment_group" "habit_market_server" {
  app_name              = aws_codedeploy_app.habit_market_server.name
  deployment_group_name = "habit-market-server-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy.arn

  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"

  ecs_service {
    cluster_name = var.ecs_cluster_name
    service_name = aws_ecs_service.habit_market_server.name
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }

    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    green_fleet_provisioning_option {
      action = "COPY_AUTO_SCALING_GROUP"
    }
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.habit_market_server.arn]
      }

      target_group {
        name = aws_lb_target_group.habit_market_server.name
      }

      target_group {
        name = aws_lb_target_group.habit_market_server_green.name
      }
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  tags = {
    Name = "habit-market-server-deployment-group"
  }
}

# ECS Service
resource "aws_ecs_service" "habit_market_server" {
  name            = "habit-market-server"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.habit_market_server.arn
  desired_count   = 1

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.habit_market_server.arn
    container_name   = "habit-market-server"
    container_port   = 8080
  }

  depends_on = [
    aws_lb_listener.habit_market_server,
    aws_iam_role_policy.ecs_task_execution_secrets,
    aws_iam_role_policy.ecs_task_secrets
  ]

  tags = {
    Name = "habit-market-server-service"
  }

  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }
}

# ALB Listener
resource "aws_lb_listener" "habit_market_server" {
  load_balancer_arn = var.alb_arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.habit_market_server.arn
  }
}
