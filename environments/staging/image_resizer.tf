data "aws_iam_policy_document" "image_resizer_s3" {
  statement {
    sid       = "ReadUploads"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/*"]
  }

  statement {
    sid       = "WriteThumbnails"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:PutObjectAcl"]
    resources = ["${aws_s3_bucket.thumbnails.arn}/*"]
  }
}

module "image_resizer" {
  source = "../../modules/lambda-fn"

  name        = "${local.name}-image-resizer"
  description = "Resizes uploaded images into thumbnails"

  image_uri = "${module.image_resizer_ecr.repository_url}:${var.image_resizer_tag}"

  memory_mb            = 1536
  timeout_seconds      = 60
  ephemeral_storage_mb = 1024
  architectures        = ["arm64"]
  tracing_mode         = "Active"

  environment_variables = {
    THUMBNAIL_BUCKET = aws_s3_bucket.thumbnails.id
    THUMBNAIL_PREFIX = "thumbs/"
    LOG_LEVEL        = "info"
  }

  inline_policies = {
    s3-rw = data.aws_iam_policy_document.image_resizer_s3.json
  }

  s3_event_sources = {
    uploads = {
      bucket_arn    = aws_s3_bucket.uploads.arn
      events        = ["s3:ObjectCreated:*"]
      filter_prefix = "uploads/"
    }
  }

  log_retention_days  = 30
  alarm_sns_topic_arn = aws_sns_topic.alerts.arn

  tags = local.common_tags
}

module "api" {
  source = "../../modules/api-gateway"

  name        = "${local.name}-api"
  description = "Catalog staging API"

  lambda_integrations = {
    resizer = {
      function_name = module.image_resizer.function_name
      invoke_arn    = module.image_resizer.invoke_arn
    }
  }

  routes = {
    "POST /thumbnails" = { integration = "resizer" }
  }

  cors_configuration = {
    allow_origins = ["https://app.staging.example.com"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
    max_age       = 300
  }

  default_route_throttling_burst_limit = 500
  default_route_throttling_rate_limit  = 1000

  access_log_retention_days = 30
  alarm_sns_topic_arn       = aws_sns_topic.alerts.arn

  tags = local.common_tags
}
