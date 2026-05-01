module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  cidr_block         = var.vpc_cidr
  availability_zones = var.availability_zones

  single_nat_gateway         = false
  enable_s3_gateway_endpoint = true
  enable_ecr_endpoints       = true
  enable_flow_logs           = true
  flow_logs_retention_days   = 90

  tags = local.common_tags
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
