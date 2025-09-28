variable "container_registry_arn_list" {
  description = "A list of ARNs for container registries."
  type        = list(string)
}

# Unique per AWS account. Already defined in keone.dev.
data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

# define an IAM Role in AWS that trusts this OIDC provider and grants the necessary permissions.
resource "aws_iam_role" "github_actions_ecr_uploader" {
  name = "github-actions-ecr-uploader"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com",
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" : "repo:dan-kc/habit-market-backend:*"
          }
        }
      }
    ]
  })
}

# Policy to interact with ECR
resource "aws_iam_policy" "ecr_upload_policy" {
  name        = "github-actions-ecr-upload-policy"
  description = "Allows GitHub Actions to push images to ECR"

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
  role       = aws_iam_role.github_actions_ecr_uploader.name
  policy_arn = aws_iam_policy.ecr_upload_policy.arn
}
