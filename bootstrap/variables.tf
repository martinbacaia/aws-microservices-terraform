variable "region" {
  description = "AWS region where the state bucket and lock table will be created. State buckets are regional; pick once and stick with it."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the S3 bucket that holds remote Terraform state for all environments."
  type        = string
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  type        = string
  default     = "terraform-state-locks"
}

variable "force_destroy" {
  description = "Allow destroying the bucket even if it contains state objects. Keep false in real environments to prevent state loss."
  type        = bool
  default     = false
}
