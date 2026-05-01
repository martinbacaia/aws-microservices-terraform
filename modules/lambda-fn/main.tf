###############################################################################
# Lambda function with IAM role, log group, optional VPC config, optional S3
# event sources, optional function URL, optional DLQ, optional alarms.
###############################################################################

locals {
  base_tags = merge(
    {
      "Name"      = var.name
      "Module"    = "lambda-fn"
      "ManagedBy" = "terraform"
    },
    var.tags,
  )

  is_zip   = var.filename != null
  is_image = var.image_uri != null

  # Compute log group name up front so the IAM policy can reference it before
  # the function (which would also create a log group implicitly).
  log_group_name = "/aws/lambda/${var.name}"

  in_vpc = length(var.vpc_subnet_ids) > 0

  # Default duration alarm to 80% of timeout if caller did not set one.
  duration_alarm_ms = var.duration_alarm_threshold_ms != null ? var.duration_alarm_threshold_ms : floor(var.timeout_seconds * 1000 * 0.8)
}

###############################################################################
# Validation we cannot do as variable validations (cross-variable).
###############################################################################
resource "terraform_data" "validate_source" {
  lifecycle {
    precondition {
      condition     = (local.is_zip && !local.is_image) || (!local.is_zip && local.is_image)
      error_message = "Provide exactly one of filename (+ handler + runtime) or image_uri."
    }
    precondition {
      condition     = !local.is_zip || (var.handler != null && var.runtime != null)
      error_message = "When filename is set, both handler and runtime are required."
    }
  }
}

###############################################################################
# IAM role.
###############################################################################
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-lambda"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.base_tags
}

# Logs policy — explicit, scoped to the function's own log group rather than
# attaching the AWSLambdaBasicExecutionRole managed policy (which is `*`).
data "aws_iam_policy_document" "logs" {
  statement {
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "${aws_cloudwatch_log_group.this.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "logs" {
  name   = "logs"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.logs.json
}

# VPC ENI permissions — only when in_vpc.
resource "aws_iam_role_policy_attachment" "vpc" {
  count = local.in_vpc ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# DLQ publish.
data "aws_iam_policy_document" "dlq" {
  count = var.dead_letter_target_arn == null ? 0 : 1

  statement {
    actions = [
      "sns:Publish",
      "sqs:SendMessage",
    ]
    resources = [var.dead_letter_target_arn]
  }
}

resource "aws_iam_role_policy" "dlq" {
  count = var.dead_letter_target_arn == null ? 0 : 1

  name   = "dlq-publish"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.dlq[0].json
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

###############################################################################
# Log group — pre-created so retention is enforced from day one.
###############################################################################
resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = local.base_tags
}

###############################################################################
# Optional dedicated SG for the function (only when in VPC).
###############################################################################
resource "aws_security_group" "this" {
  count = local.in_vpc ? 1 : 0

  name        = "${var.name}-lambda"
  description = "Lambda function ${var.name}"
  vpc_id      = data.aws_subnet.first[0].vpc_id

  tags = merge(local.base_tags, { Name = "${var.name}-lambda" })
}

resource "aws_vpc_security_group_egress_rule" "lambda_all" {
  count = local.in_vpc ? 1 : 0

  security_group_id = aws_security_group.this[0].id
  description       = "Lambda needs outbound for AWS API calls and any backing services"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

data "aws_subnet" "first" {
  count = local.in_vpc ? 1 : 0
  id    = var.vpc_subnet_ids[0]
}

###############################################################################
# Function.
###############################################################################
resource "aws_lambda_function" "this" {
  function_name = var.name
  description   = var.description
  role          = aws_iam_role.this.arn

  # zip-mode args
  filename         = local.is_zip ? var.filename : null
  source_code_hash = local.is_zip ? coalesce(var.source_code_hash, try(filebase64sha256(var.filename), null)) : null
  handler          = local.is_zip ? var.handler : null
  runtime          = local.is_zip ? var.runtime : null

  # image-mode args
  package_type = local.is_image ? "Image" : "Zip"
  image_uri    = local.is_image ? var.image_uri : null

  memory_size   = var.memory_mb
  timeout       = var.timeout_seconds
  architectures = var.architectures

  ephemeral_storage {
    size = var.ephemeral_storage_mb
  }

  reserved_concurrent_executions = var.reserved_concurrent_executions

  kms_key_arn = var.kms_key_arn

  tracing_config {
    mode = var.tracing_mode
  }

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  dynamic "vpc_config" {
    for_each = local.in_vpc ? [1] : []
    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = concat([aws_security_group.this[0].id], var.vpc_security_group_ids)
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.dead_letter_target_arn == null ? [] : [1]
    content {
      target_arn = var.dead_letter_target_arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy.logs,
    terraform_data.validate_source,
  ]

  tags = local.base_tags
}

###############################################################################
# X-Ray tracing — Active mode requires a managed policy attachment.
###############################################################################
resource "aws_iam_role_policy_attachment" "xray" {
  count = var.tracing_mode == "Active" ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

###############################################################################
# Function URL (optional).
###############################################################################
resource "aws_lambda_function_url" "this" {
  count = var.create_function_url ? 1 : 0

  function_name      = aws_lambda_function.this.function_name
  authorization_type = var.function_url_auth_type
}

###############################################################################
# S3 event sources.
###############################################################################
# Lambda permission per source bucket: "s3:::bucket" can invoke the function.
resource "aws_lambda_permission" "s3" {
  for_each = var.s3_event_sources

  statement_id  = "AllowS3Invoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = each.value.bucket_arn
}

# Bucket notification — note that S3 only allows ONE notification config
# per bucket. If the bucket has other notifications, manage them all
# together in a single resource at the env composition level instead of
# using this module's notification creation.
resource "aws_s3_bucket_notification" "this" {
  for_each = var.s3_event_sources

  bucket = regex("arn:aws:s3:::(.+)", each.value.bucket_arn)[0]

  lambda_function {
    id                  = "${var.name}-${each.key}"
    lambda_function_arn = aws_lambda_function.this.arn
    events              = each.value.events
    filter_prefix       = each.value.filter_prefix
    filter_suffix       = each.value.filter_suffix
  }

  depends_on = [aws_lambda_permission.s3]
}

###############################################################################
# Alarms.
###############################################################################
resource "aws_cloudwatch_metric_alarm" "errors" {
  count = var.alarm_sns_topic_arn == null ? 0 : 1

  alarm_name          = "${var.name}-errors"
  alarm_description   = "Lambda ${var.name} returning errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.errors_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]

  tags = local.base_tags
}

resource "aws_cloudwatch_metric_alarm" "throttles" {
  count = var.alarm_sns_topic_arn == null ? 0 : 1

  alarm_name          = "${var.name}-throttles"
  alarm_description   = "Lambda ${var.name} being throttled — likely concurrency cap or account limit"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }

  alarm_actions = [var.alarm_sns_topic_arn]

  tags = local.base_tags
}

resource "aws_cloudwatch_metric_alarm" "duration" {
  count = var.alarm_sns_topic_arn == null ? 0 : 1

  alarm_name          = "${var.name}-duration-high"
  alarm_description   = "Lambda ${var.name} p95 duration over threshold (likely heading to timeout)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p95"
  threshold           = local.duration_alarm_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }

  alarm_actions = [var.alarm_sns_topic_arn]

  tags = local.base_tags
}
