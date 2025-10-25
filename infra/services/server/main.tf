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
          name  = "SSL_MODE"
          value = "require"
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

      # healthCheck = {
      #   command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      #   interval    = 30
      #   timeout     = 5
      #   retries     = 3
      #   startPeriod = 30
      # }
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
# Manages the underlying EC2 instances, ensuring a desired number 
# of instances are running and handling instance health.
## HERE
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

  # This is a crucial tag that allows the ECS Agent on the instances 
  # to register them with ECS as container instances.
  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

# ECS Capacity Provider
# Manages how ECS tasks are placed on that infrastructure. It tells 
# ECS where to run tasks and how to scale the ASG based on task demand.
resource "aws_ecs_capacity_provider" "ec2" {
  name = "habit-market-ec2-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_instances.arn

    managed_scaling {
      status                    = "ENABLED" # Allow ECS to manage the scaling of the linked ASG.
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
    # If multiple default capacity providers were specified, 
    # this one would get a weight of 1. Since it's the only 
    # one, all tasks using the default strategy will go here.
    weight = 1
    # ECS will always attempt to launch at least 1 task on 
    # this capacity provider before considering other options 
    # (if any were present). In this case, it means the first 
    # task will definitely use this provider.
    base = 1
  }
}

# Blue Target Group for ALB
resource "aws_lb_target_group" "habit_market_server" {
  name     = "habit-market-server-tg-blue"
  port     = 8080 # Expect traffic on port 8080 from the load balancer.
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  # Register targets based on their IP addresses. This is common for ECS 
  # Fargate tasks and ECS EC2 tasks in awsvpc network mode.
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

# Green Target Group for ALB (The new one)
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

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

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
  ]

  tags = {
    Name = "habit-market-server-service"
  }

  # Do not consider changes to the task_definition and load_balancer 
  # attributes as reasons to update or replace the ECS service 
  # after its initial creation.

  # - Normally, when you update your task_definition (e.g., change 
  #   the Docker image, add environment variables), Terraform would 
  #   want to update the task_definition attribute on the aws_ecs_service.

  # - However, with CodeDeploy, CodeDeploy itself manages the update of 
  #   the task_definition for the ECS service during a blue/green 
  #   deployment. When CodeDeploy creates the new "green" version of 
  #   the service, it updates the task_definition to point to the new one.

  # - If Terraform were to try to update task_definition concurrently or 
  #   based on its own plan, it could conflict with or break CodeDeploy's 
  #   process. By ignoring it, you're telling Terraform to trust CodeDeploy 
  #   to handle the task_definition updates.

  # - Similarly, the load_balancer block within an ECS service defines the 
  #   initial (blue) target group that the service is connected to.

  # - During a blue/green deployment, CodeDeploy is responsible for shifting 
  #   traffic between the initial ("blue") target group and the new 
  #   ("green") target group. It does this by modifying the ALB listener 
  #   rules, not by changing the load_balancer configuration on the ECS 
  #   service itself (which always points to the "blue" group, and the 
  #   "green" group is dynamically registered/deregistered by CodeDeploy).
  #
  # - If Terraform were to try and manage changes to this load_balancer block 
  #   after CodeDeploy takes over, it could interfere with the traffic routing 
  #   managed by CodeDeploy.

  # In essence, lifecycle { ignore_changes = [...] } in this context allows 
  # Terraform to manage the initial setup of the ECS service, but then cede 
  # control over task_definition and load_balancer updates to AWS CodeDeploy, 
  # preventing potential conflicts during subsequent deployments.
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
