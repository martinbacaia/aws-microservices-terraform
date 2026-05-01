variable "name" {
  description = "Bucket name. Must be globally unique."
  type        = string
}

variable "versioning_enabled" {
  description = "Whether to enable object versioning. Default true — almost always what you want."
  type        = bool
  default     = true
}

variable "sse_algorithm" {
  description = "Server-side encryption algorithm. AES256 (S3-managed) or aws:kms (custom CMK)."
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be AES256 or aws:kms."
  }
}

variable "kms_key_arn" {
  description = "KMS CMK ARN. Required when sse_algorithm = aws:kms."
  type        = string
  default     = null
}

variable "block_public_access" {
  description = "Apply the four-flag public access block. Default true; only flip for buckets that intentionally serve public objects (rare)."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete a non-empty bucket. Keep false for anything holding data."
  type        = bool
  default     = false
}

###############################################################################
# Lifecycle — one optional rule covering the common cases. For multi-rule
# setups, add `aws_s3_bucket_lifecycle_configuration` outside the module.
###############################################################################
variable "expiration_days" {
  description = "Delete current object versions after N days. null = no expiration rule."
  type        = number
  default     = null
}

variable "noncurrent_version_expiration_days" {
  description = "Delete noncurrent (overwritten) versions after N days. null = no rule. Only meaningful when versioning is enabled."
  type        = number
  default     = null
}

variable "abort_incomplete_multipart_days" {
  description = "Abort and clean up multipart uploads older than this. Cheap insurance against orphaned parts costing money silently."
  type        = number
  default     = 7
}

###############################################################################
# Optional bucket policy — pass full JSON if the bucket needs additional
# statements (e.g. ALB access logs need the ELB service-account PutObject).
###############################################################################
variable "policy_json" {
  description = "Bucket policy as a JSON document. null = module installs only the TLS-only deny rule. When provided, the caller is responsible for including the TLS-only statement (helper outputs `tls_only_statement_json` for convenience)."
  type        = string
  default     = null
}

variable "deny_insecure_transport" {
  description = "Add a `Deny aws:SecureTransport=false` statement to the policy. Default true. Forced off only if you provide a fully custom policy that already includes equivalent enforcement."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
