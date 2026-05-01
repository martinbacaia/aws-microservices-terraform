module "products_api" {
  source = "../../modules/ecs-service"

  name               = "${local.name}-products-api"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  image          = "${module.products_api_ecr.repository_url}:${var.products_api_image_tag}"
  container_port = 8080
  task_cpu       = 1024
  task_memory_mb = 2048

  environment_variables = {
    APP_ENV   = "prod"
    PORT      = "8080"
    LOG_LEVEL = "warn"
  }

  secret_arns = {
    DATABASE_SECRET = module.rds.secret_arn
  }

  alb_listener_arn      = module.alb.https_listener_arn
  alb_security_group_id = module.alb.security_group_id
  alb_arn_suffix        = module.alb.alb_arn_suffix
  path_patterns         = ["/products", "/products/*"]
  listener_rule_priority = 100
  health_check_path     = "/health"

  desired_count       = 4
  min_healthy_percent = 100
  max_percent         = 200

  log_retention_days  = 90
  alarm_sns_topic_arn = aws_sns_topic.alerts.arn

  tags = local.common_tags
}
