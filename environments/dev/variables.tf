variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project prefix used in resource names."
  type        = string
  default     = "catalog"
}

variable "vpc_cidr" {
  description = "VPC CIDR for dev."
  type        = string
  default     = "10.10.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy across."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "products_api_image_tag" {
  description = "Image tag for products-api. Initially `bootstrap` (a placeholder image you tag once); CI overrides per deploy."
  type        = string
  default     = "bootstrap"
}

variable "image_resizer_tag" {
  description = "Image tag for image-resizer Lambda."
  type        = string
  default     = "bootstrap"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener. If null, the ALB serves HTTP only (acceptable for dev)."
  type        = string
  default     = null
}

variable "alarm_email" {
  description = "Email address subscribed to the alerts SNS topic. null = no subscription (you can subscribe manually later)."
  type        = string
  default     = null
}

variable "additional_tags" {
  description = "Tags merged into every resource."
  type        = map(string)
  default     = {}
}
