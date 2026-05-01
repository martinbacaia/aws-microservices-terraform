###############################################################################
# Application Load Balancer + dedicated SG + listeners.
#
# This module deliberately does NOT create target groups or listener rules.
# Those belong to the service that owns the workload (see ecs-service module),
# so a single ALB can host many services without the ALB module knowing about
# any of them.
###############################################################################

locals {
  base_tags = merge(
    {
      "Name"      = var.name
      "Module"    = "alb"
      "ManagedBy" = "terraform"
    },
    var.tags,
  )
}

resource "aws_security_group" "this" {
  name        = "${var.name}-alb"
  description = "Ingress to ALB ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.base_tags, { Name = "${var.name}-alb" })
}

# HTTP ingress — kept open even when HTTPS is on, because the listener does a
# 301 redirect to HTTPS. Browsers and curl benefit.
resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "HTTP from ${each.key}"
  cidr_ipv4         = each.key
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = var.enable_https ? toset(var.ingress_cidr_blocks) : toset([])

  security_group_id = aws_security_group.this.id
  description       = "HTTPS from ${each.key}"
  cidr_ipv4         = each.key
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# Egress to anywhere on the VPC — the ALB has to reach target IPs in private
# subnets. Restricting by SG instead of CIDR would require knowing target SGs
# at module-build time; this is the standard pattern for shared ALBs.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "ALB → targets"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

###############################################################################
# The ALB itself.
###############################################################################
resource "aws_lb" "this" {
  name                       = var.name
  internal                   = var.internal
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.this.id]
  subnets                    = var.public_subnet_ids
  idle_timeout               = var.idle_timeout
  drop_invalid_header_fields = var.drop_invalid_header_fields
  enable_deletion_protection = var.deletion_protection
  enable_http2               = true

  dynamic "access_logs" {
    for_each = var.access_logs_bucket == null ? [] : [1]
    content {
      bucket  = var.access_logs_bucket
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  tags = local.base_tags
}

###############################################################################
# HTTP listener — either redirects to HTTPS (when enable_https) or serves a
# 404 placeholder so the listener exists and can have rules attached later.
###############################################################################
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.enable_https ? "redirect" : "fixed-response"

    dynamic "redirect" {
      for_each = var.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "fixed_response" {
      for_each = var.enable_https ? [] : [1]
      content {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }

  tags = local.base_tags
}

###############################################################################
# HTTPS listener — fixed-response by default; service modules attach rules.
###############################################################################
resource "aws_lb_listener" "https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  tags = local.base_tags

  lifecycle {
    precondition {
      condition     = var.certificate_arn != null
      error_message = "enable_https = true requires certificate_arn to be set."
    }
  }
}
