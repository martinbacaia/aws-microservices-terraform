output "function_name" {
  description = "Function name."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "Function ARN — what API Gateway and EventBridge integrations reference."
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Invoke ARN — distinct from function ARN; used in API Gateway integration_uri."
  value       = aws_lambda_function.this.invoke_arn
}

output "qualified_arn" {
  description = "Function ARN with the version suffix."
  value       = aws_lambda_function.this.qualified_arn
}

output "role_arn" {
  description = "ARN of the IAM role assumed by the function."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Function role name — for attaching extra policies after the fact."
  value       = aws_iam_role.this.name
}

output "log_group_name" {
  description = "CloudWatch log group name."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "CloudWatch log group ARN."
  value       = aws_cloudwatch_log_group.this.arn
}

output "function_url" {
  description = "Public HTTPS URL of the function (null if not enabled)."
  value       = try(aws_lambda_function_url.this[0].function_url, null)
}

output "security_group_id" {
  description = "SG attached to the function (null when not in VPC)."
  value       = try(aws_security_group.this[0].id, null)
}
