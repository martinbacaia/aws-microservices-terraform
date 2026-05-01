###############################################################################
# S3 buckets — uploads (Lambda input), thumbnails (Lambda output), ALB logs.
#
# Suffix random to keep names globally unique without baking the account id
# into the resource name.
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
resource "aws_s3_bucket" "uploads" {
  bucket = "${local.name}-uploads-${local.bucket_suffix}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

###############################################################################
# Thumbnails bucket — Lambda output. Same hardening.
###############################################################################
resource "aws_s3_bucket" "thumbnails" {
  bucket = "${local.name}-thumbnails-${local.bucket_suffix}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "thumbnails" {
  bucket = aws_s3_bucket.thumbnails.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "thumbnails" {
  bucket = aws_s3_bucket.thumbnails.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "thumbnails" {
  bucket                  = aws_s3_bucket.thumbnails.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "thumbnails" {
  bucket = aws_s3_bucket.thumbnails.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

###############################################################################
# ALB access logs bucket. ELB needs a specific bucket policy granting it
# PutObject — the policy below is the minimum AWS requires.
###############################################################################
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${local.name}-alb-logs-${local.bucket_suffix}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration { days = 90 }
  }
}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid       = "ELBAccessLogsPut"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }

  statement {
    sid       = "AWSLogDeliveryWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSLogDeliveryAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.alb_logs.arn]

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
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
