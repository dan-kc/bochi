variable "vpc_id" {
  type        = string
  description = "ID of the VPC"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for ECS tasks"
}

variable "ecs_cluster_id" {
  type        = string
  description = "ID of the ECS cluster"
}

variable "ecs_cluster_name" {
  type        = string
  description = "Name of the ECS cluster"
}

variable "database_security_group_id" {
  type        = string
  description = "Security group ID of the RDS database"
}

variable "database_secret_arn" {
  type        = string
  description = "ARN of the secret containing database credentials"
}

variable "database_kms_key_arn" {
  type        = string
  description = "ARN of the KMS key used for database secrets"
}

variable "ecr_repository_url" {
  type        = string
  description = "URL of the ECR repository for the server image"
}

variable "alb_arn" {
  type        = string
  description = "ARN of the Application Load Balancer"
}

variable "alb_security_group_id" {
  type        = string
  description = "Security group ID of the Application Load Balancer"
}