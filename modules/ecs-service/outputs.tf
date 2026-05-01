output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "ECS service ARN."
  value       = aws_ecs_service.this.id
}

output "cluster_arn" {
  description = "ARN of the cluster the service runs in (created or passed in)."
  value       = local.resolved_cluster_arn
}

output "cluster_name" {
  description = "Cluster name."
  value       = local.create_cluster ? aws_ecs_cluster.this[0].name : split("/", local.resolved_cluster_arn)[1]
}

output "task_definition_arn" {
  description = "Latest task definition ARN."
  value       = aws_ecs_task_definition.this.arn
}

output "task_role_arn" {
  description = "ARN of the task IAM role. Use this to attach extra app-specific policies after the fact."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Task role name."
  value       = aws_iam_role.task.name
}

output "execution_role_arn" {
  description = "ARN of the task execution IAM role."
  value       = aws_iam_role.execution.arn
}

output "security_group_id" {
  description = "Tasks SG. Pass this to RDS / other backing services so they can ingress from this service."
  value       = aws_security_group.tasks.id
}

output "target_group_arn" {
  description = "ALB target group ARN."
  value       = aws_lb_target_group.this.arn
}

output "log_group_name" {
  description = "Container log group name."
  value       = aws_cloudwatch_log_group.this.name
}
