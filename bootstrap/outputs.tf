output "state_bucket_name" {
  description = "Name of the S3 bucket used for remote state. Plug into backend.tf of every environment."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the state bucket. Useful for IAM policies that grant CI access."
  value       = aws_s3_bucket.state.arn
}

output "lock_table_name" {
  description = "DynamoDB table for state locking."
  value       = aws_dynamodb_table.lock.name
}

output "kms_key_arn" {
  description = "KMS key encrypting the state bucket. CI roles must be able to Decrypt this key."
  value       = aws_kms_key.state.arn
}

output "region" {
  description = "Region the backend lives in."
  value       = var.region
}
