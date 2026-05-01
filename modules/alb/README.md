# Module: `alb`

Application Load Balancer with HTTP→HTTPS redirect, dedicated SG, and S3
access logs.

## What it builds

- `aws_security_group` allowing :80 (and :443 if HTTPS enabled) from the
  configured ingress CIDRs
- `aws_lb` (application, internet-facing or internal)
- `aws_lb_listener` on :80 — 301 redirect to HTTPS when `enable_https = true`,
  otherwise a 404 fixed response
- `aws_lb_listener` on :443 (when enabled) with a 404 default action and the
  ACM certificate attached
- Optional access logs to S3

## What it does NOT build

Target groups and listener rules. Those belong to the **services** behind the
ALB (the `ecs-service` module attaches its own target group and a listener
rule for path-based routing). One ALB → N services without the ALB module
knowing about any of them.

## Why a 404 default action

So the listeners always exist, even before any service is wired up. Service
modules attach `aws_lb_listener_rule` resources matching their host/path and
forward to their target group; anything that doesn't match returns 404
instead of returning the AWS load balancer's default error page.

## Inputs (selected)

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Prefix |
| `vpc_id` | string | — | VPC |
| `public_subnet_ids` | list(string) | — | ≥ 2 subnets in different AZs |
| `internal` | bool | `false` | true = internal-only ALB |
| `ingress_cidr_blocks` | list(string) | `["0.0.0.0/0"]` | Restrict for internal ALBs |
| `certificate_arn` | string | `null` | Required if HTTPS enabled |
| `enable_https` | bool | `true` | Create HTTPS listener + redirect |
| `ssl_policy` | string | `ELBSecurityPolicy-TLS13-1-2-2021-06` | TLS 1.3 baseline |
| `deletion_protection` | bool | `false` | Always true in prod |
| `drop_invalid_header_fields` | bool | `true` | Modern security default |
| `access_logs_bucket` | string | `null` | S3 bucket for access logs |

## Outputs

| Name | Description |
|---|---|
| `alb_arn` | LB ARN |
| `alb_dns_name` | DNS name |
| `alb_zone_id` | For Route 53 alias |
| `security_group_id` | Reference from target SGs |
| `http_listener_arn` / `https_listener_arn` | For attaching rules |

## Example

```hcl
module "alb" {
  source = "../../modules/alb"

  name              = "catalog-dev"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  enable_https    = true
  certificate_arn = aws_acm_certificate.api.arn

  deletion_protection = false
  access_logs_bucket  = aws_s3_bucket.alb_logs.id
}
```
