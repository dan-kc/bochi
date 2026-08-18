variable "container_registry_arn_list" {
  description = "A list of ARNs for container registries."
  type        = list(string)
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster that CircleCI deploys into"
  type        = string
}

variable "server_service_name" {
  description = "Name of the ECS service that CircleCI updates"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where Fargate tasks will run"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of private subnets for Fargate tasks"
  type        = list(string)
}

variable "database_security_group_id" {
  description = "Security group ID of the RDS database"
  type        = string
}

variable "migration_repository_url" {
  description = "URL of the ECR repository containing Flyway migration image"
  type        = string
}

variable "database_secret_arn" {
  description = "ARN of the secret containing database credentials"
  type        = string
}

variable "database_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt database secrets"
  type        = string
}

variable "database_endpoint" {
  description = "RDS endpoint used by Flyway migration tasks"
  type        = string
}
