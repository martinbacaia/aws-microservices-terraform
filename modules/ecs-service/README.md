# Module: `ecs-service`

End-to-end ECS Fargate service: cluster (optional), task definition, service,
target group, listener rule, IAM roles split between execution and task,
log group, and alarms.

## What it builds

- `aws_ecs_cluster` (with Container Insights and `FARGATE` + `FARGATE_SPOT`
  capacity providers) — **only if `cluster_arn` is null**, so multiple
  services can share a cluster
- `aws_iam_role` × 2:
  - **Execution role** — pulls from ECR, writes to CloudWatch Logs, reads
    declared secrets from Secrets Manager (scoped to the ARNs you list)
  - **Task role** — what the application itself uses; caller supplies
    policies via `task_role_policy_arns` and/or `task_role_inline_policies`
- `aws_security_group` for tasks — only ALB SG can ingress on
  `container_port`, no CIDRs
- `aws_ecs_task_definition` (Fargate, `awsvpc`, x86_64, with secrets injected
  as env vars)
- `aws_lb_target_group` (`target_type = "ip"`, configurable health check)
- `aws_lb_listener_rule` (host and/or path patterns)
- `aws_ecs_service` with circuit breaker, deployment min/max, health check
  grace period, ECS Exec optional
- `aws_cloudwatch_log_group` with retention
- 3 conditional `aws_cloudwatch_metric_alarm`: unhealthy targets, service
  CPU > 85, running task count < desired

## Why two IAM roles?

This is the bit reviewers look for. Mixing them is a red flag.

| Role | Assumed by | Should be allowed to |
|---|---|---|
| **Execution role** | The ECS agent (out-of-band of your code) | Pull image from ECR, write to its own log group, fetch the secrets you declared |
| **Task role** | The application code (via `169.254.170.2` task metadata) | Anything the app needs to do — call S3, DynamoDB, etc. |

The execution role gets a tightly scoped Secrets Manager policy: only
`GetSecretValue` and only on the ARNs in `secret_arns`. Not `*`.

## Listener attachment

The module **does not own the ALB**. It attaches a listener rule
(`host_header_patterns` and/or `path_patterns`) to a listener ARN you pass
in. The `alb` module exposes `https_listener_arn`. Routing example:

```hcl
host_header_patterns   = ["api.dev.example.com"]
path_patterns          = ["/products", "/products/*"]
listener_rule_priority = 100
```

The lifecycle precondition refuses to create a rule with neither host nor
path conditions.

## Inputs (selected — see `variables.tf` for all)

| Group | Key vars |
|---|---|
| Cluster | `cluster_arn`, `cluster_name_override`, `container_insights_enabled` |
| Task | `image`, `container_port`, `task_cpu`, `task_memory_mb`, `environment_variables`, `secret_arns` |
| IAM | `task_role_policy_arns`, `task_role_inline_policies` |
| Service | `desired_count`, `min_healthy_percent`, `max_percent`, `enable_execute_command`, `deployment_circuit_breaker` |
| ALB | `alb_listener_arn`, `alb_security_group_id`, `listener_rule_priority`, `host_header_patterns`, `path_patterns`, `health_check_path` |
| Obs | `log_retention_days`, `alarm_sns_topic_arn` |

## Outputs

| Name | Description |
|---|---|
| `service_arn` / `service_name` | The service |
| `cluster_arn` / `cluster_name` | Cluster (created or passed-in) |
| `task_role_arn` / `task_role_name` | For attaching extra policies |
| `execution_role_arn` | Less commonly needed |
| `security_group_id` | Use as ingress rule on RDS/other backing SGs |
| `target_group_arn` | Useful for autoscaling attachment |
| `log_group_name` | For dashboards / log subscriptions |

## Example

```hcl
module "products_api" {
  source = "../../modules/ecs-service"

  name               = "products-api"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  image          = "${module.products_ecr.repository_url}:sha-${var.image_tag}"
  container_port = 8080
  task_cpu       = 512
  task_memory_mb = 1024

  environment_variables = {
    APP_ENV = "dev"
    PORT    = "8080"
  }

  secret_arns = {
    DATABASE_URL = module.rds.secret_arn
  }

  alb_listener_arn      = module.alb.https_listener_arn
  alb_security_group_id = module.alb.security_group_id
  host_header_patterns  = ["api.dev.example.com"]
  path_patterns         = ["/products", "/products/*"]
  listener_rule_priority = 100

  desired_count       = 2
  alarm_sns_topic_arn = aws_sns_topic.alerts.arn
}

# Wire ECS task SG → RDS SG so the app can reach the DB.
# (rds-postgres module accepts ingress_security_group_ids.)
```

## Decisions

- **`ignore_changes = [task_definition]`** on the service. Image tags get
  bumped by CI on every deploy, not Terraform; without ignore_changes,
  `terraform plan` would always show drift.
- **Container Insights on by default** — costs ~$0.30 per metric per
  dashboard, but the value of `RunningTaskCount` and per-service CPU/mem
  metrics is too high to skip.
- **Spot in the capacity provider list** but `FARGATE` is the default — if
  you want spot, override `default_capacity_provider_strategy` from the env
  composition.
- **No autoscaling in this module** — autoscaling policies, target tracking,
  and the `ignore_changes = [desired_count]` flip belong in env composition.
  Keeping them out of the module avoids a "scaling on/off" boolean labyrinth.
