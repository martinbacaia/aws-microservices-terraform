###############################################################################
# Hardened S3 bucket: versioning, SSE, ownership, public-access-block, optional
# lifecycle, optional bucket policy (with TLS-only as default).
###############################################################################

locals {
  base_tags = merge(
    {
      "Name"      = var.name
      "Module"    = "s3-bucket"
      "ManagedBy" = "terraform"
    },
    var.tags,
  )

  has_lifecycle_rule = (
    var.expiration_days != null
    || var.noncurrent_version_expiration_days != null
    || var.abort_incomplete_multipart_days != null
  )
}

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy
  tags          = local.base_tags
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.sse_algorithm == "aws:kms" ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.sse_algorithm == "aws:kms"
  }

  lifecycle {
    precondition {
      condition     = var.sse_algorithm != "aws:kms" || var.kms_key_arn != null
      error_message = "kms_key_arn is required when sse_algorithm = aws:kms."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  count = var.block_public_access ? 1 : 0

  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

###############################################################################
# Lifecycle rule — single configurable rule covers the common case.
###############################################################################
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = local.has_lifecycle_rule ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    id     = "default"
    status = "Enabled"
    filter {}

    dynamic "expiration" {
      for_each = var.expiration_days == null ? [] : [var.expiration_days]
      content {
        days = expiration.value
      }
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.noncurrent_version_expiration_days == null ? [] : [var.noncurrent_version_expiration_days]
      content {
        noncurrent_days = noncurrent_version_expiration.value
      }
    }

    dynamic "abort_incomplete_multipart_upload" {
      for_each = var.abort_incomplete_multipart_days == null ? [] : [var.abort_incomplete_multipart_days]
      content {
        days_after_initiation = abort_incomplete_multipart_upload.value
      }
    }
  }
}

###############################################################################
# Bucket policy.
#
# Three modes:
#  1. Default (deny_insecure_transport = true, policy_json = null):
#     install only the TLS-only deny.
#  2. Custom policy via policy_json: caller controls everything; module does
#     not add the TLS deny (caller is expected to include it).
#  3. deny_insecure_transport = false and policy_json = null:
#     no policy at all (only for buckets that need to be truly open — rare).
###############################################################################
data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count = (var.policy_json != null) || var.deny_insecure_transport ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = var.policy_json != null ? var.policy_json : data.aws_iam_policy_document.tls_only.json
}
