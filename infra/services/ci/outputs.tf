output "migration_task_definition_arn" {
  value       = aws_ecs_task_definition.migration.arn
  description = "ARN of the ECS task definition for Flyway migrations"
}

output "migration_task_definition_family" {
  value       = aws_ecs_task_definition.migration.family
  description = "Family name of the ECS task definition for Flyway migrations"
}

output "migration_security_group_id" {
  value       = aws_security_group.migration_task.id
  description = "Security group ID for migration Fargate tasks"
}

output "migration_log_group_name" {
  value       = aws_cloudwatch_log_group.migration.name
  description = "CloudWatch log group name for migration tasks"
}

output "circleci_role_arn" {
  value       = aws_iam_role.circleci_uploader_deployer.arn
  description = "ARN of the CircleCI role for running deployments and migrations"
}

output "migration_task_role_arn" {
  value       = aws_iam_role.migration_task.arn
  description = "ARN of the IAM role for migration tasks"
}

output "migration_task_execution_role_arn" {
  value       = aws_iam_role.migration_task_execution.arn
  description = "ARN of the IAM role for migration task execution"
}