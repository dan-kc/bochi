# TASK EXECUTION
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "bochi-server-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "bochi-server-ecs-task-execution-role"
  }
}
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "bochi-server-ecs-task-execution-secrets"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          var.database_secret_arn,
          data.aws_secretsmanager_secret.jwt_keys.arn,
          data.aws_secretsmanager_secret.app_store_in_app_purchase_key.arn,
          data.aws_secretsmanager_secret.apple_sign_in_private_key.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [
          var.database_kms_key_arn,
          "*" # Allow decryption of any KMS key used by secrets
        ]
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# TASK
resource "aws_iam_role" "ecs_task_role" {
  name = "bochi-server-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "bochi-server-ecs-task-role"
  }
}

# EC2 INSTANCES
resource "aws_iam_role" "ecs_instance_role" {
  name = "bochi-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "bochi-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}
