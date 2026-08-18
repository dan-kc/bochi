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

variable "database_endpoint" {
  type        = string
  description = "Database connection endpoint"
}

variable "apple_sign_in_team_id" {
  type        = string
  description = "Apple Developer Team ID used to sign Sign in with Apple client secrets"
}

variable "apple_sign_in_key_id" {
  type        = string
  description = "Key ID for the Sign in with Apple private key"
}

variable "app_store_server_issuer_id" {
  type        = string
  description = "Issuer ID for App Store Server API JWT authentication"
}

variable "app_store_server_key_id" {
  type        = string
  description = "Key ID for the App Store Server API In-App Purchase key"
}

variable "app_store_server_bundle_id" {
  type        = string
  description = "Bundle ID used in App Store Server API JWT authentication"
}

variable "ecr_repository_url" {
  type        = string
  description = "URL of the ECR repository for the server image"
}

variable "alb_security_group_id" {
  type        = string
  description = "Security group ID of the Application Load Balancer"
}

variable "https_listener_arn" {
  type        = string
  description = "ARN of the HTTPS listener to attach rules to"
}
