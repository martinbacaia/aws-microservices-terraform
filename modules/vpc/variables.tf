variable "name" {
  description = "Name prefix applied to all VPC-scoped resources (vpc, subnets, route tables, etc). Conventionally `<project>-<env>`."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC. /16 leaves room for /20 subnets across many AZs."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR (e.g. 10.0.0.0/16)."
  }
}

variable "availability_zones" {
  description = "Names of AZs in which to create subnets. Three is the production default; two acceptable for dev."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 4
    error_message = "Provide between 2 and 4 availability zones."
  }
}

variable "single_nat_gateway" {
  description = "If true, create one NAT gateway shared by all private subnets (cheap, single-AZ failure domain). If false, one NAT per AZ (resilient, ~$32/mo extra per AZ). Default false (per-AZ)."
  type        = bool
  default     = false
}

variable "enable_s3_gateway_endpoint" {
  description = "Add an S3 gateway endpoint so S3 traffic from private subnets stays on the AWS network and incurs no NAT data-processing charges."
  type        = bool
  default     = true
}

variable "enable_ecr_endpoints" {
  description = "Add interface endpoints for ECR API + DKR + CloudWatch Logs so Fargate tasks can pull images and write logs without traversing the NAT. Costs ~$22/mo per endpoint per AZ but pays for itself for any non-trivial image pull volume."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs to CloudWatch. Strongly recommended for prod; optional for dev."
  type        = bool
  default     = false
}

variable "flow_logs_retention_days" {
  description = "CloudWatch retention for flow logs."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags merged into every resource created by the module."
  type        = map(string)
  default     = {}
}
