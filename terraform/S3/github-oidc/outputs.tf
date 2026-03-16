output "role_arn" {
  description = "ARN do IAM Role - configurar como GitHub Secret: AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "ARN do OIDC Provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_secrets_config" {
  description = "Secrets para configurar no GitHub repo"
  value = {
    AWS_ROLE_ARN = aws_iam_role.github_actions.arn
    AWS_REGION   = var.aws_region
  }
}
