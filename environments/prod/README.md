# Environment: `prod`

Production composition. Same modules as `dev` and `staging`; the differences
are in inputs and a couple of explicit safeguards.

## Diff vs `staging`

| Area | staging | prod |
|---|---|---|
| RDS | t4g.small, multi-AZ, 7d backups | m7g.large, multi-AZ, 30d backups, storage autoscaling to 500 GiB |
| ECS task | 2 × 1 vCPU / 2 GiB | 4 × 1 vCPU / 2 GiB |
| Lambda | 1.5 GiB, no DLQ | 2 GiB, reserved concurrency 50, **SQS DLQ** for async failures |
| Flow logs retention | 14d | 90d |
| Log retention | 30d | 90d |
| API throttling | 500/1000 burst/rate | 2000/5000 |
| `alarm_email` | optional | **required** (validation in `variables.tf`) |
| `image_tag` defaults | `bootstrap` placeholder | **no default** — must be passed (CI does this) |

## Hard requirements

The `variables.tf` file enforces three things via validation:

- `certificate_arn` must be set
- `alarm_email` must be set
- `products_api_image_tag` and `image_resizer_tag` are non-default — passing
  them is required on every `apply`, so you cannot accidentally redeploy a
  stale image

These fail at `terraform plan` time, before anything touches AWS.

## Deploy

Deploys are gated by the GitHub Actions workflow at
`.github/workflows/terraform-apply.yml` — manual approval required. Locally:

```bash
cd environments/prod
# make sure you are in the right AWS account
aws sts get-caller-identity

# tags come from CI; for manual deploys, set them explicitly
export TF_VAR_products_api_image_tag=v1.2.3
export TF_VAR_image_resizer_tag=v1.2.3
export TF_VAR_certificate_arn=arn:aws:acm:...
export TF_VAR_alarm_email=oncall@example.com

terraform init
terraform plan -out=plan.tfplan
# review plan carefully; have a second pair of eyes
terraform apply plan.tfplan
```

## What changes between staging and prod is *only inputs*

The infrastructure is the same Terraform code — the same modules at the
same versions, composed by environments that differ only in `tfvars` and a
handful of opinionated flags. That's the DRY case the repo is meant to
demonstrate.
