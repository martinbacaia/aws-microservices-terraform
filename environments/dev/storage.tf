###############################################################################
# Storage — three buckets via modules/s3-bucket, plus ECR repos.
#
# Bucket names share a random suffix so two envs in the same account cannot
# collide on the global S3 namespace.
###############################################################################
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_suffix = random_id.suffix.hex
}

###############################################################################
# Uploads bucket — original images land here, S3 events trigger the resizer.
###############################################################################
module "uploads_bucket" {
  source = "../../modules/s3-bucket"

  name                               = "${local.name}-uploads-${local.bucket_suffix}"
  noncurrent_version_expiration_days = 30

  tags = local.common_tags
}

###############################################################################
# Thumbnails bucket — Lambda output.
###############################################################################
module "thumbnails_bucket" {
  source = "../../modules/s3-bucket"

  name = "${local.name}-thumbnails-${local.bucket_suffix}"

  tags = local.common_tags
}

###############################################################################
# ALB access logs bucket. Needs a custom policy granting the ELB log
# delivery service principal PutObject — passed via aws_s3_bucket_policy
# outside the module so the policy can reference the module's bucket ARN.
###############################################################################
module "alb_logs_bucket" {
  source = "../../modules/s3-bucket"

  name            = "${local.name}-alb-logs-${local.bucket_suffix}"
  expiration_days = 90

  # We attach the full policy below (TLS-only + ELB delivery), so disable
  # the module's default TLS-only-only policy to avoid two policy resources
  # competing.
  deny_insecure_transport = false

  tags = local.common_tags
}

data "aws_iam_policy_document" "alb_logs" {
  # Reuse the module's TLS-only statement so we keep TLS enforcement.
  source_policy_documents = [module.alb_logs_bucket.tls_only_statement_json]

  statement {
    sid       = "ELBAccessLogsPut"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${module.alb_logs_bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }

  statement {
    sid       = "AWSLogDeliveryWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${module.alb_logs_bucket.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSLogDeliveryAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [module.alb_logs_bucket.arn]

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = module.alb_logs_bucket.id
  policy = data.aws_iam_policy_document.alb_logs.json
}

###############################################################################
# ECR repos — one per service.
###############################################################################
module "products_api_ecr" {
  source = "../../modules/ecr-repo"

  name = "${local.name}/products-api"
  tags = local.common_tags
}

module "image_resizer_ecr" {
  source = "../../modules/ecr-repo"

  name = "${local.name}/image-resizer"
  tags = local.common_tags
}
