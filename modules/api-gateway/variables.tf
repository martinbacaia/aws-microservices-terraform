variable "name" {
  description = "API name. Used as prefix for the stage name and log group."
  type        = string
}

variable "description" {
  description = "Description shown in the API Gateway console."
  type        = string
  default     = ""
}

variable "stage_name" {
  description = "Stage name. `$default` is the special stageless stage that serves at the API URL root — fine for HTTP APIs and what most setups use."
  type        = string
  default     = "$default"
}

###############################################################################
# Lambda integrations.
#
# Pass a map of logical name -> lambda metadata. The module creates one
# integration per entry plus the lambda invoke permission.
###############################################################################
variable "lambda_integrations" {
  description = <<-EOT
    Map of integration name -> Lambda config:
      function_name = lambda function name (for the InvokeFunction permission)
      invoke_arn    = the lambda module's `invoke_arn` output
      payload_format_version = "2.0" (default, recommended) or "1.0"
      timeout_ms    = 30000 default; max 30000 for HTTP APIs (29s in practice)
  EOT
  type = map(object({
    function_name          = string
    invoke_arn             = string
    payload_format_version = optional(string, "2.0")
    timeout_ms             = optional(number, 30000)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.lambda_integrations :
      contains(["1.0", "2.0"], v.payload_format_version)
    ])
    error_message = "payload_format_version must be \"1.0\" or \"2.0\"."
  }
}

###############################################################################
# Routes — mapping `route_key` (e.g. "POST /thumbnails") -> integration name.
###############################################################################
variable "routes" {
  description = <<-EOT
    Map of `route_key` -> route config:
      integration         = integration name from var.lambda_integrations
      authorization_type  = "NONE" (default) | "JWT" | "AWS_IAM"
      authorizer_key      = key into var.jwt_authorizers when authorization_type = "JWT"
      authorization_scopes = optional list of OAuth scopes (JWT only)
    Route keys follow the API Gateway HTTP API format: `METHOD /path` (e.g. `GET /products/{id}`) or `$default` for the catch-all.
  EOT
  type = map(object({
    integration          = string
    authorization_type   = optional(string, "NONE")
    authorizer_key       = optional(string)
    authorization_scopes = optional(list(string), [])
  }))
  default = {}
}

###############################################################################
# CORS — HTTP APIs handle preflight automatically when this is configured.
###############################################################################
variable "cors_configuration" {
  description = <<-EOT
    CORS config for the API. Set to null to disable. When set, API Gateway
    answers OPTIONS preflight automatically without invoking your Lambda.
  EOT
  type = object({
    allow_credentials = optional(bool, false)
    allow_headers     = optional(list(string), ["content-type", "authorization"])
    allow_methods     = optional(list(string), ["GET", "POST", "PUT", "DELETE", "OPTIONS"])
    allow_origins     = optional(list(string), ["*"])
    expose_headers    = optional(list(string), [])
    max_age           = optional(number, 0)
  })
  default = null
}

###############################################################################
# JWT authorizers (Cognito user pool or any OIDC issuer).
###############################################################################
variable "jwt_authorizers" {
  description = <<-EOT
    Map of authorizer name -> JWT config. Reference the key from a route via
    `authorization_type = "JWT"` and `authorizer_key = "<name>"`.
  EOT
  type = map(object({
    issuer             = string       # e.g. https://cognito-idp.<region>.amazonaws.com/<pool-id>
    audience           = list(string) # client ids
    identity_sources   = optional(list(string), ["$request.header.Authorization"])
  }))
  default = {}
}

###############################################################################
# Throttling.
###############################################################################
variable "default_route_throttling_burst_limit" {
  description = "Default burst limit applied to every route on the stage."
  type        = number
  default     = 500
}

variable "default_route_throttling_rate_limit" {
  description = "Default steady-state requests per second per route."
  type        = number
  default     = 1000
}

###############################################################################
# Logging.
###############################################################################
variable "access_log_retention_days" {
  description = "CloudWatch retention for the access log group."
  type        = number
  default     = 30
}

variable "kms_key_arn" {
  description = "KMS CMK for the access log group. null = AWS managed key."
  type        = string
  default     = null
}

###############################################################################
# Alarms.
###############################################################################
variable "alarm_sns_topic_arn" {
  description = "SNS topic for alarms. null = no alarms."
  type        = string
  default     = null
}

variable "alarm_5xx_threshold" {
  description = "5xx count over 5 minutes that fires the alarm."
  type        = number
  default     = 5
}

variable "alarm_4xx_ratio_threshold" {
  description = "4xx-to-total ratio over 5 minutes (0.0–1.0) that fires the alarm. 0.05 = 5%."
  type        = number
  default     = 0.05
}

variable "alarm_latency_p95_ms" {
  description = "p95 integration latency in ms over 5 minutes that fires the alarm."
  type        = number
  default     = 2000
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
