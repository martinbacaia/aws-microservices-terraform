output "id" {
  description = "Bucket name (S3 bucket id is the name)."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "regional_domain_name" {
  description = "Regional domain name — for static hosting / virtual-host-style URLs."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "tls_only_statement_json" {
  description = "JSON of the TLS-only deny statement, exposed so callers building a custom policy_json can include it."
  value       = data.aws_iam_policy_document.tls_only.json
}
