###############################################################################
# ALB — single shared ALB; the ECS service attaches its own listener rule.
###############################################################################
module "alb" {
  source = "../../modules/alb"

  name              = local.name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  enable_https        = local.enable_https
  certificate_arn     = var.certificate_arn
  deletion_protection = false

  access_logs_bucket = module.alb_logs_bucket.id
  access_logs_prefix = local.name

  tags = local.common_tags
}
