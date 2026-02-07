output "repository_urls" {
  description = "Map of repository names to URLs"
  value       = { for name, repo in aws_ecr_repository.main : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of repository names to ARNs"
  value       = { for name, repo in aws_ecr_repository.main : name => repo.arn }
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for ECR encryption"
  value       = var.create_kms_key ? aws_kms_key.ecr[0].arn : null
}
