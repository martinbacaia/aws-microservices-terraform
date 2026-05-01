module "rds" {
  source = "../../modules/rds-postgres"

  name       = "${local.name}-products"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  ingress_security_group_ids = [module.products_api.security_group_id]

  engine_version       = "16.4"
  instance_class       = "db.t4g.small"
  allocated_storage_gb = 50
  multi_az             = true

  database_name = "products"

  deletion_protection   = true
  skip_final_snapshot   = false
  backup_retention_days = 7

  alarm_sns_topic_arn = aws_sns_topic.alerts.arn

  tags = local.common_tags
}
