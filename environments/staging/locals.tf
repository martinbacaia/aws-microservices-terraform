locals {
  env  = "staging"
  name = "${var.project}-${local.env}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = local.env
    },
    var.additional_tags,
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_elb_service_account" "main" {}
