locals {
  env  = "dev"
  name = "${var.project}-${local.env}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = local.env
    },
    var.additional_tags,
  )

  enable_https = var.certificate_arn != null
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ELB account id per region — needed for the ALB access logs bucket policy.
# For us-east-1 this is 127311923021. AWS publishes the full table.
data "aws_elb_service_account" "main" {}
