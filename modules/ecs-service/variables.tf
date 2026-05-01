variable "name" {
  description = "Service name. Used as the prefix for cluster, task def family, log group, target group, and IAM roles."
  type        = string
}

variable "vpc_id" {
  description = "VPC where tasks and the target group live."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets where Fargate task ENIs are placed."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "Provide at least one private subnet."
  }
}

###############################################################################
# Cluster — module creates one by default; pass an existing cluster ARN to
# share across services.
###############################################################################
variable "cluster_arn" {
  description = "Existing ECS cluster ARN to deploy into. If null, the module creates a dedicated cluster (with Container Insights)."
  type        = string
  default     = null
}

variable "cluster_name_override" {
  description = "If creating a cluster, override its name. Defaults to var.name."
  type        = string
  default     = null
}

variable "container_insights_enabled" {
  description = "Enable Container Insights on the created cluster. Costs ~$0.30 per metric per CW dashboard but gives ECS-native dashboards."
  type        = bool
  default     = true
}

###############################################################################
# Task definition — container shape.
###############################################################################
variable "image" {
  description = "Container image URI (typically `<account>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>`)."
  type        = string
}

variable "container_port" {
  description = "Port exposed by the container — also the target group target port."
  type        = number
  default     = 8080
}

variable "container_command" {
  description = "Override the image CMD. Empty list = use the image default."
  type        = list(string)
  default     = []
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = .25 vCPU, 512 = .5, 1024 = 1, 2048 = 2)."
  type        = number
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.task_cpu)
    error_message = "task_cpu must be a valid Fargate CPU size."
  }
}

variable "task_memory_mb" {
  description = "Fargate task memory MiB. Must be a valid combination with task_cpu — see the Fargate docs table."
  type        = number
  default     = 1024
}

variable "environment_variables" {
  description = "Plain environment variables passed to the container."
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "Map of `ENV_VAR_NAME` -> Secrets Manager ARN (or SSM SecureString ARN). The container receives the resolved secret value as an env var. Execution role gets read access automatically."
  type        = map(string)
  default     = {}
}

variable "task_role_policy_arns" {
  description = "Managed/customer policy ARNs to attach to the *task* role (the role the application uses to call AWS). Execution role permissions are handled by the module."
  type        = list(string)
  default     = []
}

variable "task_role_inline_policies" {
  description = "Map of inline policy name -> JSON policy document, attached to the task role. Use for tightly scoped per-service permissions."
  type        = map(string)
  default     = {}
}

###############################################################################
# Service shape & rollout.
###############################################################################
variable "desired_count" {
  description = "Number of running tasks."
  type        = number
  default     = 2
}

variable "min_healthy_percent" {
  description = "Percentage of desired_count that must remain running during a deploy."
  type        = number
  default     = 100
}

variable "max_percent" {
  description = "Maximum percentage of desired_count during a deploy. 200 = double-up before draining old tasks."
  type        = number
  default     = 200
}

variable "health_check_grace_period_seconds" {
  description = "Time in seconds after a task starts before health checks count against it."
  type        = number
  default     = 60
}

variable "enable_execute_command" {
  description = "Enable ECS Exec (SSM-backed shell into running tasks). Useful for ops; off by default."
  type        = bool
  default     = false
}

variable "deployment_circuit_breaker" {
  description = "Auto-rollback failed deployments. Disable only if you have a custom rollback strategy."
  type        = bool
  default     = true
}

###############################################################################
# ALB integration.
###############################################################################
variable "alb_listener_arn" {
  description = "ARN of the ALB listener (HTTPS preferred) where this service attaches its routing rule."
  type        = string
}

variable "alb_security_group_id" {
  description = "ALB security group id — used to allow ingress from ALB to tasks on container_port."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB (`app/<name>/<id>`) used as the LoadBalancer dimension on UnHealthyHostCount alarm. Output as `arn_suffix` by the alb module. Required when alarm_sns_topic_arn is set."
  type        = string
  default     = null
}

variable "listener_rule_priority" {
  description = "Priority of the listener rule. Must be unique per listener. Lower = evaluated first."
  type        = number
  default     = 100
}

variable "host_header_patterns" {
  description = "Host header patterns the listener rule matches on (e.g. [\"api.example.com\"]). Empty list disables host matching."
  type        = list(string)
  default     = []
}

variable "path_patterns" {
  description = "Path patterns the listener rule matches on (e.g. [\"/products\", \"/products/*\"]). Empty list disables path matching."
  type        = list(string)
  default     = ["/*"]
}

variable "health_check_path" {
  description = "Target group HTTP health check path."
  type        = string
  default     = "/health"
}

variable "health_check_matcher" {
  description = "HTTP status range that counts as healthy."
  type        = string
  default     = "200-299"
}

variable "health_check_interval" {
  description = "Seconds between health checks."
  type        = number
  default     = 30
}

variable "deregistration_delay" {
  description = "Seconds the LB waits before deregistering a draining target. Lower = faster deploys, risk of dropped requests."
  type        = number
  default     = 30
}

###############################################################################
# Observability.
###############################################################################
variable "log_retention_days" {
  description = "CloudWatch log retention for the container log group."
  type        = number
  default     = 30
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic for alarms. null = no alarms."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
