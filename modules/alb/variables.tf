variable "name" {
  description = "Name prefix for the ALB and related resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC where the ALB and SG live."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets the ALB attaches to. Must be public for an internet-facing ALB."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "ALB requires at least 2 subnets in different AZs."
  }
}

variable "internal" {
  description = "If true the ALB is internal (no public IPs, only reachable from inside the VPC). Default is internet-facing."
  type        = bool
  default     = false
}

variable "ingress_cidr_blocks" {
  description = "CIDRs allowed to hit the ALB on HTTP/HTTPS. Default 0.0.0.0/0 because that's the point of an internet-facing ALB. For internal ALBs, restrict to the VPC CIDR."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener. Required if `enable_https = true`."
  type        = string
  default     = null
}

variable "enable_https" {
  description = "Create the HTTPS:443 listener and HTTP→HTTPS redirect. If false, the ALB serves plain HTTP (only useful in dev when you don't have a cert yet)."
  type        = bool
  default     = true
}

variable "ssl_policy" {
  description = "ELB SSL policy on the HTTPS listener. The TLS-1-2-Ext-2018-06 policy is the modern default; FS-1-2-Res-2020-10 is stricter."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "deletion_protection" {
  description = "Prevents the LB from being destroyed by `terraform destroy`. Always true in prod."
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "Idle connection timeout in seconds."
  type        = number
  default     = 60
}

variable "drop_invalid_header_fields" {
  description = "ALB drops headers that don't match RFC 7230. Default true to match modern security guidance."
  type        = bool
  default     = true
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs. If null, access logs are not enabled."
  type        = string
  default     = null
}

variable "access_logs_prefix" {
  description = "Prefix within the access logs bucket. Useful when the bucket is shared across LBs."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
