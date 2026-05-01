variable "name" {
  description = "Identifier prefix for the DB instance and related resources. Conventionally `<project>-<env>-<service>`."
  type        = string
}

variable "vpc_id" {
  description = "VPC where the DB lives. Must contain the subnets in `subnet_ids`."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet ids for the DB subnet group. Need at least two AZs even for single-AZ deployments — RDS requires it."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS requires a subnet group with at least 2 AZs."
  }
}

variable "ingress_security_group_ids" {
  description = "Security groups allowed to reach the DB on the Postgres port. Pass the ECS service SG (and bastion SG if applicable). Empty by default — pass at least one or the DB is unreachable."
  type        = list(string)
  default     = []
}

variable "engine_version" {
  description = "Postgres major.minor. Pin to a maintained version; AWS announces deprecations 12 months out."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "DB instance class. Use db.t4g.micro for dev, db.m7g.large or up for prod."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Initial allocated storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Upper bound for storage autoscaling. Set higher than `allocated_storage_gb` to enable autoscaling."
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "Storage type. gp3 is the right default — cheaper than gp2 and tunable IOPS."
  type        = string
  default     = "gp3"
}

variable "multi_az" {
  description = "Enable Multi-AZ failover. true for prod; false for dev (saves ~50%)."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "How many days of automated backups to keep. AWS minimum is 0; 7 is the practical floor for prod."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 0 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 0 and 35."
  }
}

variable "deletion_protection" {
  description = "If true, the DB cannot be deleted via the API. Always true in prod."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "If true, no final snapshot on destroy. Acceptable for dev only."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights. Free for the 7-day retention tier; very useful when something is slow."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for encryption at rest and Performance Insights. If null, AWS-managed `aws/rds` is used."
  type        = string
  default     = null
}

variable "database_name" {
  description = "Initial database created on the instance."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username. Postgres reserves `postgres` and a few others — anything else works."
  type        = string
  default     = "appadmin"
}

variable "log_retention_days" {
  description = "Retention for the Postgres CloudWatch log group."
  type        = number
  default     = 30
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN that CloudWatch alarms publish to. Pass null to skip alarm creation entirely."
  type        = string
  default     = null
}

variable "cpu_alarm_threshold" {
  description = "Average CPU % over 5 minutes that triggers the high-CPU alarm."
  type        = number
  default     = 80
}

variable "free_storage_alarm_bytes" {
  description = "Trigger alarm when FreeStorageSpace drops below this many bytes (default 5 GiB)."
  type        = number
  default     = 5368709120
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}
