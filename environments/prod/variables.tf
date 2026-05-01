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
  description = "VPC CIDR for prod."
  type        = string
  default     = "10.30.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy across."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "products_api_image_tag" {
  description = "Image tag for products-api. Bumped by CI on each release."
  type        = string
}

variable "image_resizer_tag" {
  description = "Image tag for image-resizer."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener."
  type        = string

  validation {
    condition     = var.certificate_arn != null
    error_message = "certificate_arn is required for prod."
  }
}

variable "alarm_email" {
  description = "Email subscribed to alerts SNS topic."
  type        = string

  validation {
    condition     = var.alarm_email != null
    error_message = "alarm_email is required for prod — alarms must be received by someone."
  }
}

variable "additional_tags" {
  description = "Tags merged everywhere."
  type        = map(string)
  default     = {}
}
