# Environment: `dev`

Dev composition of the catalog stack. Cheap by default: single NAT, single-AZ
RDS, smallest viable instance sizes, no deletion protection.

## What it builds

| Block | Module | What |
|---|---|---|
| Networking | `vpc` | VPC, 3 AZs, single NAT, S3 gateway endpoint |
| Storage | inline | S3 buckets: `uploads/`, `thumbnails/`, `alb-logs/` (all encrypted, versioned, public-blocked) |
| Storage | `ecr-repo` ×2 | One ECR repo per service |
| Database | `rds-postgres` | Single-AZ Postgres 16, t4g.micro, ingress only from products-api SG |
| Edge | `alb` | One ALB in public subnets, optional HTTPS via ACM |
| Service | `ecs-service` | products-api on Fargate, behind the ALB, talks to RDS |
| Service | `lambda-fn` | image-resizer triggered by S3 uploads, writes thumbnails |
| Edge | `api-gateway` | HTTP API exposing the resizer at `POST /thumbnails` |
| Alerts | inline | SNS topic + optional email subscription |

## Cost optimisations vs prod

- `single_nat_gateway = true` (~$32/mo savings)
- `multi_az = false` on RDS (~50% savings)
- `instance_class = db.t4g.micro` (free tier eligible)
- `desired_count = 1` on ECS
- `min_healthy_percent = 50` (rolls with one task)
- `enable_ecr_endpoints = false` (interface endpoints are ~$22/mo per AZ)
- `enable_flow_logs = false` (storage cost)
- `deletion_protection = false`, `skip_final_snapshot = true`

## Quickstart

```bash
# 1. Bootstrap the remote state (run-once per account; see ../../bootstrap)
cd ../../bootstrap && terraform init && terraform apply

# 2. Update backend.tf in this directory with the bucket name from step 1.

# 3. Initialise & apply
cd ../environments/dev
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars

terraform init
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```

After apply, push the initial container images:

```bash
# Get login
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin "$(terraform output -raw products_api_ecr_url)"

# products-api
docker build -t catalog/products-api ./services/products-api
docker tag  catalog/products-api:latest "$(terraform output -raw products_api_ecr_url):bootstrap"
docker push "$(terraform output -raw products_api_ecr_url):bootstrap"

# image-resizer
docker build -t catalog/image-resizer ./services/image-resizer
docker tag  catalog/image-resizer:latest "$(terraform output -raw image_resizer_ecr_url):bootstrap"
docker push "$(terraform output -raw image_resizer_ecr_url):bootstrap"
```

> The `services/` directories are out of scope for this IaC repo. The
> point of this stack is the infrastructure; the application code lives in
> separate repos and CI pushes its image tags here.

## Try it

```bash
# Drop an image into uploads/ — the resizer fires
aws s3 cp ./photo.jpg "s3://$(terraform output -raw uploads_bucket)/uploads/photo.jpg"

# Wait a few seconds, then list thumbnails
aws s3 ls "s3://$(terraform output -raw thumbnails_bucket)/thumbs/"

# Hit the API directly
curl -X POST "$(terraform output -raw api_invoke_url)/thumbnails" \
  -H 'Content-Type: application/json' \
  -d '{"key":"uploads/photo.jpg"}'
```

## Tear down

```bash
# Empty the buckets first — Terraform refuses to destroy non-empty buckets
# (and that's deliberate; force_destroy is off).
aws s3 rm "s3://$(terraform output -raw uploads_bucket)" --recursive
aws s3 rm "s3://$(terraform output -raw thumbnails_bucket)" --recursive
aws s3 rm "s3://$(terraform output -json | jq -r '.alb_logs_bucket // empty')" --recursive 2>/dev/null

terraform destroy
```

If `terraform destroy` errors on the ALB logs bucket, empty it the same way
and re-run.
