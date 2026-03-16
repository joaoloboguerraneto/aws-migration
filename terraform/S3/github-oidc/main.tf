resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # Thumbprint do GitHub Actions OIDC - valor fixo e público
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "github-actions-oidc"
  }
}

resource "aws_iam_role" "github_actions" {
  name        = "${var.project_name}-github-actions-role"
  description = "Role assumida pelo GitHub Actions via OIDC para CI/CD"

  # Trust policy - só permite este repo específico
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubOIDC"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # Restringe ao repositório específico
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Permite branches main/develop e GitHub Environments
            "token.actions.githubusercontent.com:sub" = concat(
              [
                "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
                "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/develop",
                "repo:${var.github_org}/${var.github_repo}:pull_request",
              ],
              [for env in var.environments :
                "repo:${var.github_org}/${var.github_repo}:environment:${env}"
              ]
            )
          }
        }
      }
    ]
  })

  # Limitar duração da sessão (1 hora - suficiente para CI/CD)
  max_session_duration = 3600

  tags = {
    Name        = "${var.project_name}-github-actions"
    Purpose     = "CI/CD"
    GitHubRepo  = "${var.github_org}/${var.github_repo}"
  }
}

# ─────────────────────────────────────────────
# Permissões - o que o pipeline pode fazer
# ─────────────────────────────────────────────

# 1. ECR - push/pull de imagens Docker
resource "aws_iam_role_policy" "ecr_access" {
  name = "ecr-push-pull"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}/*"
      }
    ]
  })
}

# 2. EKS - acesso ao cluster para deploy
resource "aws_iam_role_policy" "eks_access" {
  name = "eks-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSDescribe"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.project_name}-*"
      }
    ]
  })
}

# 3. Terraform - permissões para gerir a infraestrutura
# Em produção, considerar usar roles separadas por environment com permissões mais restritas
resource "aws_iam_role_policy" "terraform_infra" {
  name = "terraform-infra-management"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-tfstate-*",
          "arn:aws:s3:::${var.project_name}-tfstate-*/*"
        ]
      },
      {
        Sid    = "TerraformLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-terraform-locks"
      },
      {
        Sid    = "TerraformInfra"
        Effect = "Allow"
        Action = [
          # VPC
          "ec2:*",
          # EKS
          "eks:*",
          # RDS
          "rds:*",
          # ELB
          "elasticloadbalancing:*",
          # WAF
          "wafv2:*",
          # IAM (limitado a resources deste projeto)
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PassRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",
          "iam:GetRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:CreateOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:TagPolicy",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:ListInstanceProfilesForRole",
          # KMS
          "kms:*",
          # CloudWatch
          "cloudwatch:*",
          "logs:*",
          # S3 (para ALB logs, etc.)
          "s3:*",
          # Secrets Manager
          "secretsmanager:*",
          # SNS
          "sns:*",
          # STS (para verificações)
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      }
    ]
  })
}
