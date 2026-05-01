###############################################################################
# ECS Fargate service: cluster (optional), task definition, service, target
# group, listener rule, IAM roles, log group, alarms.
#
# Roles split:
#   - execution role: used by the ECS agent to pull from ECR, push logs to
#     CloudWatch, fetch secrets from Secrets Manager. App code never assumes it.
#   - task role: assumed by the app code (via the task metadata endpoint).
#     Carries app-specific permissions (S3, DynamoDB, etc.) — caller supplies.
###############################################################################

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition = data.aws_partition.current.partition
  region    = data.aws_region.current.name
  account   = data.aws_caller_identity.current.account_id

  cluster_name = coalesce(var.cluster_name_override, var.name)
  create_cluster = var.cluster_arn == null
  resolved_cluster_arn = local.create_cluster ? aws_ecs_cluster.this[0].arn : var.cluster_arn

  log_group_name = "/aws/ecs/${var.name}"

  base_tags = merge(
    {
      "Name"      = var.name
      "Module"    = "ecs-service"
      "ManagedBy" = "terraform"
    },
    var.tags,
  )

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = var.image
      essential = true
      command   = length(var.container_command) > 0 ? var.container_command : null

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        },
      ]

      environment = [
        for k, v in var.environment_variables : { name = k, value = v }
      ]

      secrets = [
        for k, arn in var.secret_arns : { name = k, valueFrom = arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.log_group_name
          "awslogs-region"        = local.region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      readonlyRootFilesystem = false
      # Container-level health check is intentionally omitted; the ALB target
      # group health check is the source of truth.
    }
  ])
}

###############################################################################
# Cluster (only if caller did not pass one).
###############################################################################
resource "aws_ecs_cluster" "this" {
  count = local.create_cluster ? 1 : 0

  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = var.container_insights_enabled ? "enabled" : "disabled"
  }

  tags = local.base_tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  count = local.create_cluster ? 1 : 0

  cluster_name       = aws_ecs_cluster.this[0].name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

###############################################################################
# Log group.
###############################################################################
resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  tags              = local.base_tags
}

###############################################################################
# Execution role — pulls images, writes logs, reads secrets.
###############################################################################
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.base_tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The managed policy above grants ECR + Logs but NOT Secrets Manager. Add a
# scoped inline policy that only grants GetSecretValue on the specific ARNs
# the caller asked for.
data "aws_iam_policy_document" "execution_secrets" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = values(var.secret_arns)
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  name   = "secrets-read"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets[0].json
}

###############################################################################
# Task role — what the app code itself can do. Caller supplies the policies.
###############################################################################
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.base_tags
}

resource "aws_iam_role_policy_attachment" "task_managed" {
  for_each = toset(var.task_role_policy_arns)

  role       = aws_iam_role.task.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "task_inline" {
  for_each = var.task_role_inline_policies

  name   = each.key
  role   = aws_iam_role.task.id
  policy = each.value
}

###############################################################################
# Security group for tasks — only ALB SG can reach :container_port.
###############################################################################
resource "aws_security_group" "tasks" {
  name        = "${var.name}-tasks"
  description = "ECS tasks for ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.base_tags, { Name = "${var.name}-tasks" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_to_tasks" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "ALB to container port"
  referenced_security_group_id = var.alb_security_group_id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "tasks_all" {
  security_group_id = aws_security_group.tasks.id
  description       = "Tasks need outbound: ECR, Secrets Manager, RDS, etc."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

###############################################################################
# Task definition.
###############################################################################
resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  cpu                      = var.task_cpu
  memory                   = var.task_memory_mb
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = local.container_definitions

  tags = local.base_tags
}

###############################################################################
# Target group + listener rule.
###############################################################################
resource "aws_lb_target_group" "this" {
  name        = substr("${var.name}-tg", 0, 32) # ALB TG names cap at 32 chars
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # required for awsvpc/Fargate

  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    interval            = var.health_check_interval
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    protocol            = "HTTP"
  }

  tags = local.base_tags

  # AWS recreates a target group if name changes; lifecycle prevents
  # accidental in-place rename collisions during deploys.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "this" {
  listener_arn = var.alb_listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  dynamic "condition" {
    for_each = length(var.host_header_patterns) > 0 ? [1] : []
    content {
      host_header {
        values = var.host_header_patterns
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.path_patterns) > 0 ? [1] : []
    content {
      path_pattern {
        values = var.path_patterns
      }
    }
  }

  tags = local.base_tags

  lifecycle {
    precondition {
      condition     = length(var.host_header_patterns) + length(var.path_patterns) > 0
      error_message = "At least one of host_header_patterns or path_patterns must be non-empty."
    }
  }
}

###############################################################################
# Service.
###############################################################################
resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = local.resolved_cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  enable_execute_command = var.enable_execute_command
  propagate_tags         = "SERVICE"

  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  deployment_minimum_healthy_percent = var.min_healthy_percent
  deployment_maximum_percent         = var.max_percent

  deployment_circuit_breaker {
    enable   = var.deployment_circuit_breaker
    rollback = var.deployment_circuit_breaker
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.name
    container_port   = var.container_port
  }

  # Without this, every plan after a deploy via CI shows desired_count drift
  # if autoscaling is in play. Keep desired_count managed by Terraform unless
  # the env composition wires up app autoscaling — then ignore it.
  lifecycle {
    ignore_changes = [task_definition] # task def churn happens via CI image bumps
  }

  depends_on = [
    aws_lb_listener_rule.this,
    aws_iam_role_policy_attachment.execution_managed,
  ]

  tags = local.base_tags
}

###############################################################################
# Alarms.
###############################################################################
resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  count = var.alarm_sns_topic_arn == null ? 0 : 1

  alarm_name          = "${var.name}-unhealthy-targets"
  alarm_description   = "ALB target group ${var.name} has unhealthy targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.this.arn_suffix
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]

  tags = local.base_tags

  lifecycle {
    precondition {
      condition     = var.alb_arn_suffix != null
      error_message = "alb_arn_suffix is required when alarm_sns_topic_arn is set (it forms the LoadBalancer dimension)."
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "service_cpu_high" {
  count = var.alarm_sns_topic_arn == null ? 0 : 1

  alarm_name          = "${var.name}-cpu-high"
  alarm_description   = "ECS service ${var.name} CPU > 85%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.create_cluster ? aws_ecs_cluster.this[0].name : split("/", local.resolved_cluster_arn)[1]
    ServiceName = aws_ecs_service.this.name
  }

  alarm_actions = [var.alarm_sns_topic_arn]

  tags = local.base_tags
}

resource "aws_cloudwatch_metric_alarm" "service_running_count" {
  count = var.alarm_sns_topic_arn == null ? 0 : 1

  alarm_name          = "${var.name}-running-count-low"
  alarm_description   = "ECS service ${var.name} running task count below desired"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Minimum"
  threshold           = var.desired_count
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = local.create_cluster ? aws_ecs_cluster.this[0].name : split("/", local.resolved_cluster_arn)[1]
    ServiceName = aws_ecs_service.this.name
  }

  alarm_actions = [var.alarm_sns_topic_arn]

  tags = local.base_tags
}
