module "alb" {
  source = "../../modules/alb"

  name              = local.name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  enable_https        = true
  certificate_arn     = var.certificate_arn
  deletion_protection = true

  access_logs_bucket = aws_s3_bucket.alb_logs.id
  access_logs_prefix = local.name

  tags = local.common_tags
}
