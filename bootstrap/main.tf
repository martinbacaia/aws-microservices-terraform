###############################################################################
# Terraform backend bootstrap.
#
# This stack is the chicken-and-egg solution for "I want remote state but I
# need infra to host it". Run it ONCE per AWS account using a *local* state
# file (do not configure a backend here). After it succeeds, the rest of the
# repo points its backend at the bucket+table created here.
###############################################################################

# Account and partition info — used so the bucket policy is portable across
# regions/govcloud and to derive the KMS key alias account scope.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

###############################################################################
# KMS key for state-at-rest encryption. SSE-S3 is fine, but a CMK gives us
# auditable key usage in CloudTrail and the ability to revoke access in an
# incident.
###############################################################################
resource "aws_kms_key" "state" {
  description             = "Encrypts Terraform remote state in S3"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.state_bucket_name}"
  target_key_id = aws_kms_key.state.key_id
}

###############################################################################
# State bucket. Versioning is non-negotiable: state corruption is recoverable
# only if old object versions still exist.
###############################################################################
resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket_name
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Belt-and-suspenders: require TLS for any access to state objects.
resource "aws_s3_bucket_policy" "state_tls_only" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })
}

# Old state versions still cost money. Trim them after a year — long enough
# to recover from "oops I rolled back six months", short enough to stop the
# bill from creeping.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-state"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

###############################################################################
# DynamoDB lock table. PAY_PER_REQUEST avoids the "I forgot to scale this"
# trap — locking traffic is tiny.
###############################################################################
resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}
