###############################################################################
# RDS Postgres — small, single-AZ, no deletion protection (dev).
#
# Ingress is granted to the products-api task SG, which means we have a
# circular reference: RDS module wants the ECS SG, ECS module wants the RDS
# secret ARN. Terraform handles it because the SGs themselves do not depend
# on each other (RDS SG ingress references ECS SG by id, computed after both
# exist).
###############################################################################
module "rds" {
  source = "../../modules/rds-postgres"

  name       = "${local.name}-products"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  ingress_security_group_ids = [module.products_api.security_group_id]

  engine_version       = "16.4"
  instance_class       = "db.t4g.micro"
  allocated_storage_gb = 20
  multi_az             = false

  database_name = "products"

  deletion_protection   = false
  skip_final_snapshot   = true
  backup_retention_days = 1

  alarm_sns_topic_arn = aws_sns_topic.alerts.arn

  tags = local.common_tags
}
