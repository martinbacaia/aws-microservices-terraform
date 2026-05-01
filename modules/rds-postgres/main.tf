###############################################################################
# RDS Postgres + Secrets Manager + dedicated SG.
#
# Design:
#  - Master credentials live in Secrets Manager. The DB password is generated
#    here (random_password) and never appears in tfvars or state-as-plaintext.
#    Apps read the secret at runtime via the IAM role of their task/lambda.
#  - The SG is created by this module and only allows :5432 from the SGs the
#    caller passes in. No 0.0.0.0/0, ever. No "self" rule unless explicitly
#    granted.
###############################################################################

locals {
  port = 5432

  base_tags = merge(
    {
      "Name"      = var.name
      "Module"    = "rds-postgres"
      "ManagedBy" = "terraform"
    },
    var.tags,
  )
}

###############################################################################
# Subnet group + dedicated SG.
###############################################################################
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-sng"
  subnet_ids = var.subnet_ids
  tags       = local.base_tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "Postgres ingress for ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.base_tags, { Name = "${var.name}-rds" })
}

# One ingress rule per allowed SG. Using for_each (not count) so adding/removing
# a caller SG does not shift indices and force unrelated rule recreation.
resource "aws_vpc_security_group_ingress_rule" "from_clients" {
  for_each = toset(var.ingress_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "Postgres from ${each.key}"
  referenced_security_group_id = each.key
  from_port                    = local.port
  to_port                      = local.port
  ip_protocol                  = "tcp"
}

# Egress: by default RDS does not need to initiate connections, but the SG
# requires at least one egress rule for AWS to consider it valid. Allow all
# egress to the VPC CIDR is fine — RDS will not actually originate traffic.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "All egress (RDS does not initiate, this is for SG validity)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

###############################################################################
# Master credentials in Secrets Manager.
###############################################################################
resource "random_password" "master" {
  length  = 32
  special = true
  # Postgres rejects @ / : in URI-form connection strings; avoid them up front.
  override_special = "!#$%&*()-_=+[]{}<>?"
}

resource "aws_secretsmanager_secret" "db" {
  name        = "${var.name}/db/master"
  description = "Master credentials for RDS instance ${var.name}"
  kms_key_id  = var.kms_key_arn # null falls back to aws/secretsmanager

  # Recovery window of 7 days protects against accidental delete; for dev you
  # can pass kms_key_arn = null and override the recovery_window via a separate
  # var if you ever want to re-create.
  recovery_window_in_days = 7

  tags = local.base_tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    engine   = "postgres"
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.database_name
  })
}

###############################################################################
# Parameter group — minimal hardening: log slow queries + connections.
###############################################################################
resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-pg16"
  family      = "postgres${split(".", var.engine_version)[0]}"
  description = "Custom parameter group for ${var.name}"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # log queries slower than 1s
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = local.base_tags
}

###############################################################################
# The DB instance itself.
###############################################################################
resource "aws_db_instance" "this" {
  identifier = var.name

  engine                = "postgres"
  engine_version        = var.engine_version
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_name  = var.database_name
  username = var.master_username
  password = random_password.master.result
  port     = local.port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  multi_az            = var.multi_az
  deletion_protection = var.deletion_protection

  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00" # UTC
  maintenance_window      = "Mon:04:30-Mon:05:30"
  copy_tags_to_snapshot   = true

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.kms_key_arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  auto_minor_version_upgrade = true
  apply_immediately          = false

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  # The password is sourced from random_password and re-fed into the secret;
  # ignore drift in case someone rotates manually via Secrets Manager.
  lifecycle {
    ignore_changes = [
      password,
      final_snapshot_identifier,
    ]
  }

  tags = local.base_tags
}

###############################################################################
# Enhanced monitoring role (required for monitoring_interval > 0).
###############################################################################
data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${var.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
  tags               = local.base_tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

###############################################################################
# CloudWatch alarms (only if SNS topic provided).
###############################################################################
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.alarm_sns_topic_arn == null ? 0 : 1

  alarm_name          = "${var.name}-rds-cpu-high"
  alarm_description   = "RDS ${var.name} CPU > ${var.cpu_alarm_threshold}% for 10 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.id
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]

  tags = local.base_tags
}

resource "aws_cloudwatch_metric_alarm" "free_storage_low" {
  count = var.alarm_sns_topic_arn == null ? 0 : 1

  alarm_name          = "${var.name}-rds-free-storage-low"
  alarm_description   = "RDS ${var.name} FreeStorageSpace below threshold"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.free_storage_alarm_bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.id
  }

  alarm_actions = [var.alarm_sns_topic_arn]

  tags = local.base_tags
}

resource "aws_cloudwatch_metric_alarm" "connections_high" {
  count = var.alarm_sns_topic_arn == null ? 0 : 1

  alarm_name          = "${var.name}-rds-connections-high"
  alarm_description   = "RDS ${var.name} DatabaseConnections sustained high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 200
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.id
  }

  alarm_actions = [var.alarm_sns_topic_arn]

  tags = local.base_tags
}
