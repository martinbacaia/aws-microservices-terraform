data "aws_iam_policy_document" "image_resizer_s3" {
  statement {
    sid       = "ReadUploads"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${module.uploads_bucket.arn}/*"]
  }

  statement {
    sid       = "WriteThumbnails"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:PutObjectAcl"]
    resources = ["${module.thumbnails_bucket.arn}/*"]
  }
}

# Dead-letter SQS for async invocation failures.
resource "aws_sqs_queue" "image_resizer_dlq" {
  name                      = "${local.name}-image-resizer-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
  tags                      = local.common_tags
}

module "image_resizer" {
  source = "../../modules/lambda-fn"

  name        = "${local.name}-image-resizer"
  description = "Resizes uploaded images into thumbnails"

  image_uri = "${module.image_resizer_ecr.repository_url}:${var.image_resizer_tag}"

  memory_mb            = 2048
  timeout_seconds      = 60
  ephemeral_storage_mb = 2048
  architectures        = ["arm64"]
  tracing_mode         = "Active"

  reserved_concurrent_executions = 50

  environment_variables = {
    THUMBNAIL_BUCKET = module.thumbnails_bucket.id
    THUMBNAIL_PREFIX = "thumbs/"
    LOG_LEVEL        = "warn"
  }

  inline_policies = {
    s3-rw = data.aws_iam_policy_document.image_resizer_s3.json
  }

  s3_event_sources = {
    uploads = {
      bucket_arn    = module.uploads_bucket.arn
      events        = ["s3:ObjectCreated:*"]
      filter_prefix = "uploads/"
    }
  }

  dead_letter_target_arn = aws_sqs_queue.image_resizer_dlq.arn

  log_retention_days  = 90
  alarm_sns_topic_arn = aws_sns_topic.alerts.arn

  tags = local.common_tags
}

module "api" {
  source = "../../modules/api-gateway"

  name        = "${local.name}-api"
  description = "Catalog production API"

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
    allow_origins = ["https://app.example.com"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
    max_age       = 600
  }

  default_route_throttling_burst_limit = 2000
  default_route_throttling_rate_limit  = 5000

  access_log_retention_days = 90
  alarm_sns_topic_arn       = aws_sns_topic.alerts.arn

  tags = local.common_tags
}
