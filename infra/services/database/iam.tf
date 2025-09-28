# This is a standard and necessary setup for an ECS cluster using the EC2 launch type. 
# For Fargate launch types, you don't use this role, as Fargate is serverless and 
# managed by AWS; instead, Fargate tasks use an "ECS Task Role" and "ECS Task Execution Role" 
# for their own permissions.

# IAM Role for ECS EC2 Instance
resource "aws_iam_role" "ecs_instance" {
  name = "habit-market-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Policy to allow EC2 instances to attach EBS volumes
resource "aws_iam_role_policy" "ecs_instance_ebs" {
  name = "habit-market-ecs-instance-ebs-policy"
  role = aws_iam_role.ecs_instance.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:DescribeVolumes"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "habit-market-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}
