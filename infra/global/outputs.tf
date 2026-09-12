output "backend_repository_name" {
  value       = aws_ecr_repository.backend.name
  description = "ECR repository name for backend (use with tag staging or prod)"
}

output "frontend_repository_name" {
  value       = aws_ecr_repository.frontend.name
  description = "ECR repository name for frontend (use with tag staging or prod)"
}

output "backend_repository_url" {
  value       = aws_ecr_repository.backend.repository_url
  description = "ECR repository URL for backend"
}

output "frontend_repository_url" {
  value       = aws_ecr_repository.frontend.repository_url
  description = "ECR repository URL for frontend"
}

output "github_build_role_arn" {
  description = "Set as the AWS_BUILD_ROLE_ARN repository secret."
  value       = aws_iam_role.github_build.arn
}

output "github_deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN repository secret."
  value       = aws_iam_role.github_deploy.arn
}
