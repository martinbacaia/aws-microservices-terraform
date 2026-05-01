# Environment: `staging`

Staging mirrors prod for resilience and security; the differences are mostly
about scale (fewer tasks, smaller DB) and stricter rate limits than dev.

## Diff vs `dev`

| Area | dev | staging |
|---|---|---|
| NAT | single | per-AZ |
| RDS | single-AZ, t4g.micro, 1d backups | multi-AZ, t4g.small, 7d backups |
| RDS deletion | unprotected, no final snapshot | protected, final snapshot |
| ALB | optional HTTPS | HTTPS required (validation in `variables.tf`) |
| ALB | no deletion protection | deletion protection on |
| ECS task | 1 × 0.5 vCPU / 1 GiB | 2 × 1 vCPU / 2 GiB |
| Lambda | 1 GiB / 60s | 1.5 GiB / 60s |
| VPC flow logs | off | on (14d retention) |
| ECR endpoints | off | on |
| Log retention | 14d | 30d |
| API CORS | `*` | restricted to `app.staging.example.com` |

Same modules, same composition pattern. The only file-level differences are
inputs.

## Quickstart

```bash
cd environments/staging
cp terraform.tfvars.example terraform.tfvars
# fill in certificate_arn

terraform init
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```
