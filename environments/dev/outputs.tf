output "vpc_id" {
  description = "VPC id."
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "ALB DNS name — point a CNAME / Route 53 alias here."
  value       = module.alb.alb_dns_name
}

output "products_api_url" {
  description = "Base URL for products-api (resolves only if you point DNS at the ALB; otherwise hit ALB DNS directly)."
  value       = local.enable_https ? "https://${module.alb.alb_dns_name}/products" : "http://${module.alb.alb_dns_name}/products"
}

output "products_api_ecr_url" {
  description = "ECR repository for products-api — what CI pushes to."
  value       = module.products_api_ecr.repository_url
}

output "image_resizer_ecr_url" {
  description = "ECR repository for image-resizer."
  value       = module.image_resizer_ecr.repository_url
}

output "uploads_bucket" {
  description = "S3 bucket for source images. Drop a file in `uploads/` to trigger the resizer."
  value       = module.uploads_bucket.id
}

output "thumbnails_bucket" {
  description = "S3 bucket where the resizer writes thumbnails."
  value       = module.thumbnails_bucket.id
}

output "api_invoke_url" {
  description = "API Gateway invoke URL."
  value       = module.api.invoke_url
}

output "rds_endpoint" {
  description = "RDS endpoint (host:port) — only reachable from the products-api task SG."
  value       = module.rds.endpoint
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN with master credentials. The ECS task role can read it via the execution role's scoped policy."
  value       = module.rds.secret_arn
}

output "alerts_topic_arn" {
  description = "SNS topic for all alarms in this env."
  value       = aws_sns_topic.alerts.arn
}
