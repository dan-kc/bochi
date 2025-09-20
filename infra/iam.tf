# resource "aws_iam_role" "rds_cloudwatch_logs_role" {
#   name = "rds-cloudwatch-logs-role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "monitoring.rds.amazonaws.com"
#         }
#       }
#     ]
#   })
# }
#
# resource "aws_iam_role_policy_attachment" "rds_cloudwatch_write_policy_attachment" {
#   role       = aws_iam_role.rds_cloudwatch_logs_role.name
#   policy_arn = var.cloudwatch_write_policy_arn
# }
