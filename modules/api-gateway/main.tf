###############################################################################
# HTTP API Gateway with Lambda integrations, optional CORS, optional JWT
# authorizers, throttling, and alarms.
#
# Resources expected by the caller:
#   - One or more Lambda functions (use the `lambda-fn` module).
#   - This module wires routes to integrations and grants InvokeFunction.
###############################################################################

data "aws_region" "current" {}

locals {
  base_tags = merge(
    {
      "Name"      = var.name
      "Module"    = "api-gateway"
      "ManagedBy" = "terraform"
    },
    var.tags,
  )
}

###############################################################################
# API.
###############################################################################
resource "aws_apigatewayv2_api" "this" {
  name          = var.name
  description   = var.description
  protocol_type = "HTTP"

  dynamic "cors_configuration" {
    for_each = var.cors_configuration == null ? [] : [var.cors_configuration]
    content {
      allow_credentials = cors_configuration.value.allow_credentials
      allow_headers     = cors_configuration.value.allow_headers
      allow_methods     = cors_configuration.value.allow_methods
      allow_origins     = cors_configuration.value.allow_origins
      expose_headers    = cors_configuration.value.expose_headers
      max_age           = cors_configuration.value.max_age
    }
  }

  tags = local.base_tags
}

###############################################################################
# Access log group + stage.
###############################################################################
resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.name}"
  retention_in_days = var.access_log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = local.base_tags
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = var.stage_name
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.default_route_throttling_burst_limit
    throttling_rate_limit  = var.default_route_throttling_rate_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn

    # Common HTTP API access log fields. JSON keeps it queryable in Logs Insights.
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      protocol         = "$context.protocol"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
      integrationLatency = "$context.integration.latency"
      latency          = "$context.responseLatency"
    })
  }

  tags = local.base_tags
}

###############################################################################
# Integrations — one per Lambda.
###############################################################################
resource "aws_apigatewayv2_integration" "lambda" {
  for_each = var.lambda_integrations

  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value.invoke_arn
  integration_method     = "POST" # AWS_PROXY always uses POST regardless of route method
  payload_format_version = each.value.payload_format_version
  timeout_milliseconds   = each.value.timeout_ms
}

resource "aws_lambda_permission" "apigw" {
  for_each = var.lambda_integrations

  statement_id  = "AllowExecutionFromAPIGateway-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  # Scope the permission to this API only; "/*/*" allows any stage/route.
  source_arn = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

###############################################################################
# JWT authorizers.
###############################################################################
resource "aws_apigatewayv2_authorizer" "jwt" {
  for_each = var.jwt_authorizers

  api_id           = aws_apigatewayv2_api.this.id
  name             = each.key
  authorizer_type  = "JWT"
  identity_sources = each.value.identity_sources

  jwt_configuration {
    issuer   = each.value.issuer
    audience = each.value.audience
  }
}

###############################################################################
# Routes.
###############################################################################
resource "aws_apigatewayv2_route" "this" {
  for_each = var.routes

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.key

  target = "integrations/${aws_apigatewayv2_integration.lambda[each.value.integration].id}"

  authorization_type = each.value.authorization_type
  authorizer_id = (
    each.value.authorization_type == "JWT"
    ? aws_apigatewayv2_authorizer.jwt[each.value.authorizer_key].id
    : null
  )
  authorization_scopes = each.value.authorization_scopes

  lifecycle {
    precondition {
      condition = (
        each.value.authorization_type != "JWT"
        || (each.value.authorizer_key != null && contains(keys(var.jwt_authorizers), coalesce(each.value.authorizer_key, "")))
      )
      error_message = "Route ${each.key} declares authorization_type = JWT but authorizer_key is missing or does not match a key in var.jwt_authorizers."
    }
    precondition {
      condition     = contains(keys(var.lambda_integrations), each.value.integration)
      error_message = "Route ${each.key} references integration '${each.value.integration}' which is not defined in var.lambda_integrations."
    }
  }
}

###############################################################################
# Alarms.
###############################################################################
resource "aws_cloudwatch_metric_alarm" "five_xx" {
  count = var.alarm_sns_topic_arn == null ? 0 : 1

  alarm_name          = "${var.name}-5xx"
  alarm_description   = "API ${var.name} returning 5xx responses"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "5xx"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.this.id
    Stage = aws_apigatewayv2_stage.this.name
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]

  tags = local.base_tags
}

resource "aws_cloudwatch_metric_alarm" "four_xx_ratio" {
  count = var.alarm_sns_topic_arn == null ? 0 : 1

  alarm_name          = "${var.name}-4xx-ratio"
  alarm_description   = "API ${var.name} 4xx ratio above ${var.alarm_4xx_ratio_threshold * 100}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = var.alarm_4xx_ratio_threshold
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "ratio"
    expression  = "IF(total > 0, errors / total, 0)"
    label       = "4xx ratio"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "4xx"
      namespace   = "AWS/ApiGateway"
      period      = 300
      stat        = "Sum"
      dimensions = {
        ApiId = aws_apigatewayv2_api.this.id
        Stage = aws_apigatewayv2_stage.this.name
      }
    }
  }

  metric_query {
    id = "total"
    metric {
      metric_name = "Count"
      namespace   = "AWS/ApiGateway"
      period      = 300
      stat        = "Sum"
      dimensions = {
        ApiId = aws_apigatewayv2_api.this.id
        Stage = aws_apigatewayv2_stage.this.name
      }
    }
  }

  alarm_actions = [var.alarm_sns_topic_arn]

  tags = local.base_tags
}

resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  count = var.alarm_sns_topic_arn == null ? 0 : 1

  alarm_name          = "${var.name}-latency-p95"
  alarm_description   = "API ${var.name} p95 integration latency above ${var.alarm_latency_p95_ms}ms"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "IntegrationLatency"
  namespace           = "AWS/ApiGateway"
  period              = 300
  extended_statistic  = "p95"
  threshold           = var.alarm_latency_p95_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.this.id
    Stage = aws_apigatewayv2_stage.this.name
  }

  alarm_actions = [var.alarm_sns_topic_arn]

  tags = local.base_tags
}
