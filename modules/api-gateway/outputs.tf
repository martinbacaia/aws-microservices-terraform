output "api_id" {
  description = "HTTP API id."
  value       = aws_apigatewayv2_api.this.id
}

output "api_arn" {
  description = "HTTP API ARN."
  value       = aws_apigatewayv2_api.this.arn
}

output "api_endpoint" {
  description = "Default execute-api endpoint (e.g. `https://abc.execute-api.<region>.amazonaws.com`)."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "execution_arn" {
  description = "Execution ARN — use as the source_arn prefix for additional Lambda permissions."
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "stage_name" {
  description = "Stage name."
  value       = aws_apigatewayv2_stage.this.name
}

output "invoke_url" {
  description = "Full URL clients hit. For `$default` stage this is just the api_endpoint; otherwise api_endpoint/<stage>."
  value       = aws_apigatewayv2_stage.this.invoke_url
}

output "access_log_group_name" {
  description = "Access log group name."
  value       = aws_cloudwatch_log_group.access.name
}

output "integration_ids" {
  description = "Map of integration name -> integration id."
  value       = { for k, v in aws_apigatewayv2_integration.lambda : k => v.id }
}
