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
  description = "VPC CIDR for staging."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy across."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "products_api_image_tag" {
  description = "Image tag for products-api."
  type        = string
  default     = "bootstrap"
}

variable "image_resizer_tag" {
  description = "Image tag for image-resizer."
  type        = string
  default     = "bootstrap"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener. Required in staging."
  type        = string

  validation {
    condition     = var.certificate_arn != null
    error_message = "certificate_arn is required for staging — HTTPS is mandatory."
  }
}

variable "alarm_email" {
  description = "Email subscribed to alerts SNS topic."
  type        = string
  default     = null
}

variable "additional_tags" {
  description = "Tags merged everywhere."
  type        = map(string)
  default     = {}
}
