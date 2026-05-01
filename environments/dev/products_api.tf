###############################################################################
# products-api — ECS Fargate service behind the ALB, reads from RDS.
###############################################################################
module "products_api" {
  source = "../../modules/ecs-service"

  name               = "${local.name}-products-api"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  image          = "${module.products_api_ecr.repository_url}:${var.products_api_image_tag}"
  container_port = 8080
  task_cpu       = 512
  task_memory_mb = 1024

  environment_variables = {
    APP_ENV   = "dev"
    PORT      = "8080"
    LOG_LEVEL = "info"
  }

  # Inject the DB connection blob as DATABASE_SECRET. The app reads JSON.
  secret_arns = {
    DATABASE_SECRET = module.rds.secret_arn
  }

  # ALB attachment — listener depends on whether HTTPS is on.
  alb_listener_arn      = local.enable_https ? module.alb.https_listener_arn : module.alb.http_listener_arn
  alb_security_group_id = module.alb.security_group_id
  alb_arn_suffix        = module.alb.alb_arn_suffix
  path_patterns         = ["/products", "/products/*"]
  listener_rule_priority = 100
  health_check_path     = "/health"

  desired_count       = 1
  min_healthy_percent = 50  # dev — allow rolling with 1 task
  max_percent         = 200

  log_retention_days  = 14
  alarm_sns_topic_arn = aws_sns_topic.alerts.arn

  tags = local.common_tags
}
