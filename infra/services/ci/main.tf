locals {
  circleci_org_id     = "467fa236-85cd-42f9-a7cb-6acb321858bc"
  circleci_project_id = "283765cd-c505-4bab-947e-c1a53cb8db5c"
}

data "tls_certificate" "circleci" {
  url = "https://oidc.circleci.com/org/${local.circleci_org_id}"
}

# Define the AWS IAM OIDC Provider for CircleCi
# THIS IS UNIQUE PER ACCOUNT.
resource "aws_iam_openid_connect_provider" "circleci" {
  url = "https://oidc.circleci.com/org/${local.circleci_org_id}"
  # List of audience claims, sts.amazonaws.com is required for AWS STS AssumeRole
  client_id_list = [
    "sts.amazonaws.com",
    local.circleci_org_id,
  ]
  thumbprint_list = [data.tls_certificate.circleci.certificates[0].sha1_fingerprint]
}

# define an IAM Role in AWS that trusts this OIDC provider and grants the necessary permissions.
resource "aws_iam_role" "circleci_uploader_deployer" {
  name = "circleci-uploader-deployer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.circleci.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "oidc.circleci.com/org/${local.circleci_org_id}:aud" : local.circleci_org_id
            "oidc.circleci.com/org/${local.circleci_org_id}:oidc.circleci.com/project-id" : local.circleci_project_id
          }
          StringLike = {
            "oidc.circleci.com/org/${local.circleci_org_id}:sub" : "org/${local.circleci_org_id}/project/${local.circleci_project_id}/user/*/vcs-origin/github.com/dan-kc/bochi/vcs-ref/refs/heads/main"
          }
        }
      }
    ]
  })
}

# Policy to interact with ECR
resource "aws_iam_policy" "circleci_ecr_upload_policy" {
  name        = "circleci-ecr-upload-policy"
  description = "Allows CircleCi to push images to ECR"

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
        Resource = var.container_registry_arn_list
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_upload_policy_attachment" {
  role       = aws_iam_role.circleci_uploader_deployer.name
  policy_arn = aws_iam_policy.circleci_ecr_upload_policy.arn
}

# Security group for Fargate tasks
resource "aws_security_group" "migration_task" {
  name        = "bochi-migration-task-sg"
  description = "Security group for Flyway migration Fargate tasks"
  vpc_id      = var.vpc_id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name = "bochi-migration-task-sg"
  }
}

# Allow migration task to connect to database
resource "aws_security_group_rule" "database_from_migration" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.migration_task.id
  security_group_id        = var.database_security_group_id
  description              = "Allow PostgreSQL from migration tasks"
}

# CloudWatch Log Group for migration tasks
resource "aws_cloudwatch_log_group" "migration" {
  name              = "/ecs/bochi-migrations"
  retention_in_days = 7
}

# IAM role for ECS task execution
resource "aws_iam_role" "migration_task_execution" {
  name = "bochi-migration-task-execution-role"

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

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "migration_task_execution_policy" {
  role       = aws_iam_role.migration_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "migration_task_execution_secrets" {
  name = "migration-task-execution-secrets-policy"
  role = aws_iam_role.migration_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.database_secret_arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = var.database_kms_key_arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.eu-west-2.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Additional policy for ECR access
resource "aws_iam_role_policy" "migration_task_execution_ecr" {
  name = "migration-task-execution-ecr-policy"
  role = aws_iam_role.migration_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Logs permissions for execution role
resource "aws_iam_role_policy" "migration_task_execution_logs" {
  name = "migration-task-execution-logs-policy"
  role = aws_iam_role.migration_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.migration.arn}:*"
      }
    ]
  })
}

# IAM role for ECS task (runtime)
resource "aws_iam_role" "migration_task" {
  name = "bochi-migration-task-role"

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

# ECS Task Definition for Flyway migrations
resource "aws_ecs_task_definition" "migration" {
  family                   = "bochi-migrations"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.migration_task_execution.arn
  task_role_arn            = aws_iam_role.migration_task.arn

  container_definitions = jsonencode([
    {
      name  = "flyway"
      image = "${var.migration_repository_url}:latest"

      environment = [
        {
          name  = "AWS_REGION"
          value = "eu-west-2"
        },
        {
          name  = "DB_HOST"
          value = split(":", var.database_endpoint)[0]
        },
        {
          name  = "DB_NAME"
          value = "bochi"
        },
        {
          name  = "DB_PORT"
          value = "5432"
        }
      ]

      secrets = [
        {
          name      = "DB_USER"
          valueFrom = "${var.database_secret_arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.database_secret_arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.migration.name
          "awslogs-region"        = "eu-west-2"
          "awslogs-stream-prefix" = "flyway"
        }
      }

      essential = true
    }
  ])
}

# Policy for CircleCI ECS operations (migrations and deployments)
resource "aws_iam_policy" "circleci_ecs_policy" {
  name        = "circleci-ecs-policy"
  description = "Allows CircleCI to run ECS tasks and update services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask",
          "ecs:DescribeTaskDefinition"
        ]
        Resource = [
          "${aws_ecs_task_definition.migration.arn_without_revision}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeTasks",
          "ecs:StopTask"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = [
          "arn:aws:ecs:eu-west-2:*:service/${var.ecs_cluster_name}/${var.server_service_name}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.migration_task_execution.arn,
          aws_iam_role.migration_task.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.migration.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "circleci_ecs_attachment" {
  role       = aws_iam_role.circleci_uploader_deployer.name
  policy_arn = aws_iam_policy.circleci_ecs_policy.arn
}
