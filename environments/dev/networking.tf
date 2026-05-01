###############################################################################
# Networking — VPC with single NAT (dev cost optimisation), 3 AZs.
###############################################################################
module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  cidr_block         = var.vpc_cidr
  availability_zones = var.availability_zones

  # Dev cost optimisations — flip these for staging/prod.
  single_nat_gateway         = true
  enable_s3_gateway_endpoint = true # always free
  enable_ecr_endpoints       = false
  enable_flow_logs           = false

  tags = local.common_tags
}

###############################################################################
# Alerts SNS topic — used by every alarm-emitting module.
###############################################################################
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.alarm_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
