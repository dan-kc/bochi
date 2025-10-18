variable "container_registry_arn_list" {
  description = "A list of ARNs for container registries."
  type        = list(string)
}

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
