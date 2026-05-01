output "repository_url" {
  description = "Repository URL — what you `docker tag` and `docker push` to."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "Repository ARN — use this in IAM policies that grant pull/push."
  value       = aws_ecr_repository.this.arn
}
