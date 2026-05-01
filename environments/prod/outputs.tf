output "vpc_id" {
  description = "VPC id."
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "ALB DNS name."
  value       = module.alb.alb_dns_name
}

output "products_api_url" {
  description = "Base URL for products-api."
  value       = "https://${module.alb.alb_dns_name}/products"
}

output "products_api_ecr_url" {
  description = "ECR repository for products-api."
  value       = module.products_api_ecr.repository_url
}

output "image_resizer_ecr_url" {
  description = "ECR repository for image-resizer."
  value       = module.image_resizer_ecr.repository_url
}

output "uploads_bucket" {
  description = "Source images bucket."
  value       = aws_s3_bucket.uploads.id
}

output "thumbnails_bucket" {
  description = "Thumbnails bucket."
  value       = aws_s3_bucket.thumbnails.id
}

output "api_invoke_url" {
  description = "API Gateway invoke URL."
  value       = module.api.invoke_url
}

output "alerts_topic_arn" {
  description = "SNS topic for alarms."
  value       = aws_sns_topic.alerts.arn
}

output "image_resizer_dlq_arn" {
  description = "DLQ for image-resizer async failures."
  value       = aws_sqs_queue.image_resizer_dlq.arn
}
