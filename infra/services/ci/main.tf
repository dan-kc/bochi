locals {
  circleci_org_id     = "2f633adc-140c-4ef2-818e-664307d1c0a9"
  circleci_project_id = "80253561-a5bc-4229-8fa1-bcf2d834b9e2"
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

  thumbprint_list = [
    "20f540dd952c6054be3fc82f7a222a051df2b09b",
  ]
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
          StringLike = {
            "oidc.circleci.com/org/${local.circleci_org_id}:sub" : "org/${local.circleci_org_id}/project/${local.circleci_project_id}/user/*"
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
  name        = "habit-market-migration-task-sg"
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
    Name = "habit-market-migration-task-sg"
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
  name              = "/ecs/habit-market-migrations"
  retention_in_days = 7

  tags = {
    Environment = "production"
    Service     = "migrations"
  }
}

# IAM role for ECS task execution
resource "aws_iam_role" "migration_task_execution" {
  name = "habit-market-migration-task-execution-role"

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

  tags = {
    Name = "habit-market-migration-task-execution-role"
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "migration_task_execution_policy" {
  role       = aws_iam_role.migration_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
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
  name = "habit-market-migration-task-role"

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

  tags = {
    Name = "habit-market-migration-task-role"
  }
}

# Policy for task to access Secrets Manager
resource "aws_iam_role_policy" "migration_task_secrets" {
  name = "migration-task-secrets-policy"
  role = aws_iam_role.migration_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ]
        Resource = [
          var.database_secret_arn,
          "arn:aws:secretsmanager:eu-west-2:*:secret:rds!*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for task to decrypt secrets with KMS
resource "aws_iam_role_policy" "migration_task_kms" {
  name = "migration-task-kms-policy"
  role = aws_iam_role.migration_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
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

# Policy for task to write logs
resource "aws_iam_role_policy" "migration_task_logs" {
  name = "migration-task-logs-policy"
  role = aws_iam_role.migration_task.id

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


# ECS Task Definition for Flyway migrations
resource "aws_ecs_task_definition" "migration" {
  family                   = "habit-market-migrations"
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

      # The entrypoint script will detect ECS environment and fetch credentials
      environment = [
        {
          name  = "AWS_REGION"
          value = "eu-west-2"
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

  tags = {
    Name        = "habit-market-migration-task"
    Environment = "production"
  }
}

# Policy for CircleCI to run ECS tasks
resource "aws_iam_policy" "circleci_ecs_run_task_policy" {
  name        = "circleci-ecs-run-task-policy"
  description = "Allows CircleCI to run ECS Fargate tasks for database migrations"

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
          aws_ecs_task_definition.migration.arn
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

resource "aws_iam_role_policy_attachment" "circleci_ecs_run_task_attachment" {
  role       = aws_iam_role.circleci_uploader_deployer.name
  policy_arn = aws_iam_policy.circleci_ecs_run_task_policy.arn
}

# Policy for CircleCI to use CodeDeploy for ECS deployments
resource "aws_iam_policy" "circleci_codedeploy_policy" {
  name        = "circleci-codedeploy-policy"
  description = "Allows CircleCI to trigger CodeDeploy deployments for ECS services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetDeploymentGroup",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:GetApplicationRevision",
          "codedeploy:PutLifecycleEventHookExecutionStatus"
        ]
        Resource = [
          "arn:aws:codedeploy:eu-west-2:*:application:habit-market-server",
          "arn:aws:codedeploy:eu-west-2:*:deploymentgroup:habit-market-server/*",
          "arn:aws:codedeploy:eu-west-2:*:deploymentconfig:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:CreateTaskSet",
          "ecs:UpdateServicePrimaryTaskSet",
          "ecs:DeleteTaskSet",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:ModifyRule"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::*:role/habit-market-server-ecs-task-execution-role",
          "arn:aws:iam::*:role/habit-market-server-ecs-task-role"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "circleci_codedeploy_attachment" {
  role       = aws_iam_role.circleci_uploader_deployer.name
  policy_arn = aws_iam_policy.circleci_codedeploy_policy.arn
}
