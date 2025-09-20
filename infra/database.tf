# This is essentially a list of subnets that your managed database 
# service is allowed to use when creating or migrating a database instance.
# resource "aws_db_subnet_group" "default" {
#   name       = "db-subnet-group"
#   subnet_ids = [var.subnet_ip, var.subnet_ip_az2]
# }
#
#
# data "aws_secretsmanager_secret" "root_db_credentials" {
#   name = "root-db-credentials" 
# }
# data "aws_secretsmanager_secret_version" "root_db_credentials_version" {
#   secret_id = data.aws_secretsmanager_secret.root_db_credentials.id
# }
#
# resource "aws_security_group" "rds_access" {
#   name        = "rds-access"
#   description = "Allow inbound PostgreSQL traffic"
#   vpc_id      = var.vpc_id
#
#   ingress {
#     from_port       = 5432
#     to_port         = 5432
#     protocol        = "tcp"
#     security_groups = [] # TODO: Add security group for services that need.
#   }
# }
#
# resource "aws_db_instance" "db" {
#   engine                = "postgres"
#   engine_version        = "17.5"
#   instance_class        = "db.t3.micro"
#   allocated_storage     = 20
#   max_allocated_storage = 100
#   db_name               = "postgres"
#   username              = jsondecode(data.aws_secretsmanager_secret_version.root_db_credentials_version.secret_string)["username"]
#   password              = jsondecode(data.aws_secretsmanager_secret_version.root_db_credentials_version.secret_string)["password"]
#   port                  = 5432
#
#   db_subnet_group_name   = aws_db_subnet_group.default.name
#   vpc_security_group_ids = [aws_security_group.rds_access.id]
#   publicly_accessible    = false
#
#   storage_type            = "gp2"
#   skip_final_snapshot     = false
#   backup_retention_period = 7
#   multi_az                = false
#
#   # Monitoring
#   performance_insights_enabled = false
#   monitoring_interval          = 0
#
#
#   # Log Exports to CloudWatch Logs
#   # You MUST specify the role that has permissions to write to CloudWatch Logs
#   # even if you're only exporting logs.
#   # This attribute is often confused with 'monitoring_role_arn', but it's distinct
#   # and specifically for the log exports feature.
#   # For newer AWS Provider versions, you may need to use `cloudwatch_logs_export_role_arn`
#   # Check your provider version docs if `enabled_cloudwatch_logs_exports` alone isn't enough.
#   # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance#cloudwatch_logs_export_role_arn
#   # cloudwatch_logs_export_role_arn = aws_iam_role.rds_cloudwatch_logs_role.arn
#
#   enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"] # Only export the logs you are interested in
# }
