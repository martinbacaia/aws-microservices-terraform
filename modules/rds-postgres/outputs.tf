output "db_instance_id" {
  description = "DB instance identifier."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "DB instance ARN — useful for IAM resource scoping."
  value       = aws_db_instance.this.arn
}

output "endpoint" {
  description = "Connection endpoint (host:port)."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname only (no port)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Listening port."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "security_group_id" {
  description = "SG id of the DB. Reference from caller SGs to grant additional access."
  value       = aws_security_group.this.id
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding master credentials. Grant `secretsmanager:GetSecretValue` on this to consumers."
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  description = "Secret name (path-style) — what apps pass to GetSecretValue."
  value       = aws_secretsmanager_secret.db.name
}
