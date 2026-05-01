variable "name" {
  description = "Function name. Used as the prefix for IAM role and log group."
  type        = string
}

variable "description" {
  description = "Human-readable description shown in the Lambda console."
  type        = string
  default     = ""
}

###############################################################################
# Code source — exactly one of (filename + handler + runtime) or image_uri.
###############################################################################
variable "filename" {
  description = "Path to a .zip deployment package. Mutually exclusive with image_uri."
  type        = string
  default     = null
}

variable "source_code_hash" {
  description = "Base64-encoded sha256 of the deployment package. Lambda redeploys when this changes. Defaults to filebase64sha256(filename) when filename is set."
  type        = string
  default     = null
}

variable "handler" {
  description = "Function entrypoint (e.g. `index.handler`). Required when using filename."
  type        = string
  default     = null
}

variable "runtime" {
  description = "Managed runtime (e.g. `python3.12`, `nodejs20.x`). Required when using filename."
  type        = string
  default     = null
}

variable "image_uri" {
  description = "ECR image URI for container-based Lambda. Mutually exclusive with filename."
  type        = string
  default     = null
}

###############################################################################
# Runtime shape.
###############################################################################
variable "memory_mb" {
  description = "Memory in MiB. CPU scales with memory."
  type        = number
  default     = 512
}

variable "timeout_seconds" {
  description = "Function timeout. Hard cap is 900 (15 minutes)."
  type        = number
  default     = 30

  validation {
    condition     = var.timeout_seconds > 0 && var.timeout_seconds <= 900
    error_message = "timeout_seconds must be between 1 and 900."
  }
}

variable "ephemeral_storage_mb" {
  description = "/tmp size in MiB. Range 512–10240."
  type        = number
  default     = 512

  validation {
    condition     = var.ephemeral_storage_mb >= 512 && var.ephemeral_storage_mb <= 10240
    error_message = "ephemeral_storage_mb must be between 512 and 10240."
  }
}

variable "architectures" {
  description = "CPU architecture. arm64 is ~20% cheaper for compatible runtimes."
  type        = list(string)
  default     = ["arm64"]
}

variable "environment_variables" {
  description = "Environment variables passed to the function. Sensitive values should go via secret_arns and SDK calls, not env."
  type        = map(string)
  default     = {}
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrency. -1 = unreserved (account default). 0 = throttle the function entirely."
  type        = number
  default     = -1
}

variable "tracing_mode" {
  description = "X-Ray tracing mode. `Active` traces every invocation; `PassThrough` only when upstream sets the header."
  type        = string
  default     = "PassThrough"
}

###############################################################################
# Permissions.
###############################################################################
variable "policy_arns" {
  description = "Managed/customer policy ARNs to attach to the function role."
  type        = list(string)
  default     = []
}

variable "inline_policies" {
  description = "Map of inline policy name -> JSON, attached to the function role. Use for tightly scoped per-function permissions."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "Custom KMS key for env var encryption. Lambda always encrypts env vars; CMK gives you key rotation and CloudTrail of decryption."
  type        = string
  default     = null
}

###############################################################################
# Networking — VPC config is optional; functions that need RDS/private
# resources go in the VPC, others stay outside (cold-start friendlier).
###############################################################################
variable "vpc_subnet_ids" {
  description = "Private subnet ids. Empty list = function runs outside the VPC (default)."
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "Additional SGs to attach to the function ENI. The module also creates one of its own."
  type        = list(string)
  default     = []
}

###############################################################################
# Event sources.
###############################################################################
variable "s3_event_sources" {
  description = "Map of logical_name -> { bucket_arn, events, filter_prefix, filter_suffix } describing S3 → Lambda triggers. The S3 notification itself is created here; the bucket must allow it."
  type = map(object({
    bucket_arn    = string
    events        = list(string)
    filter_prefix = optional(string, "")
    filter_suffix = optional(string, "")
  }))
  default = {}
}

variable "create_function_url" {
  description = "Create a Lambda function URL (public HTTPS endpoint, IAM-authed by default)."
  type        = bool
  default     = false
}

variable "function_url_auth_type" {
  description = "Function URL auth type — NONE (public) or AWS_IAM."
  type        = string
  default     = "AWS_IAM"
}

###############################################################################
# Reliability.
###############################################################################
variable "dead_letter_target_arn" {
  description = "SNS topic or SQS queue ARN to receive async invocation failures. null = no DLQ."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 30
}

###############################################################################
# Alarms.
###############################################################################
variable "alarm_sns_topic_arn" {
  description = "SNS topic for alarms. null = no alarms."
  type        = string
  default     = null
}

variable "errors_alarm_threshold" {
  description = "Errors per 5-minute period that trigger the errors alarm."
  type        = number
  default     = 1
}

variable "duration_alarm_threshold_ms" {
  description = "p95 duration over 5 minutes that triggers the slow-invocation alarm. Default = 80% of timeout."
  type        = number
  default     = null
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
