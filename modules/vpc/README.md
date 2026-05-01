# Module: `vpc`

A three-tier-style VPC: one public subnet and one private subnet per AZ, IGW
on the public side, NAT(s) for private egress, optional VPC endpoints to keep
S3/ECR/Logs/Secrets traffic off the NAT.

## What it builds

- `aws_vpc` (DNS hostnames + support enabled)
- `aws_internet_gateway`
- N **public** `/20` subnets (one per AZ), routing `0.0.0.0/0` to IGW
- N **private** `/20` subnets (one per AZ), routing `0.0.0.0/0` to NAT
- `aws_eip` + `aws_nat_gateway` — either 1 (single-NAT mode) or N (per-AZ)
- One private route table per AZ so per-AZ NAT actually works
- Optional **S3 gateway endpoint** (free, attached to private route tables)
- Optional **interface endpoints** for `ecr.api`, `ecr.dkr`, `logs`,
  `secretsmanager` (one ENI per private subnet, ~$7/mo per ENI)
- Optional **VPC flow logs** to CloudWatch

## Subnet math

With a `/16` VPC and `cidrsubnet(cidr, 4, i)` we get 16 `/20` blocks (4096
addresses each). The module assigns:

| AZ index | Public subnet | Private subnet |
|---|---|---|
| 0 | `10.0.0.0/20` | `10.0.48.0/20` *(N=3)* |
| 1 | `10.0.16.0/20` | `10.0.64.0/20` |
| 2 | `10.0.32.0/20` | `10.0.80.0/20` |

Adding more AZs at the **end** of `availability_zones` keeps existing subnets
stable.

## When to flip `single_nat_gateway`

| Mode | Cost (NAT) | Failure domain | Use for |
|---|---|---|---|
| `true`  (single) | ~$32/mo + data | One AZ outage takes down all egress | dev, sandboxes |
| `false` (per-AZ) | ~$32/mo × N + data | One AZ outage isolates that AZ only | staging, prod |

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Name prefix applied to every resource |
| `cidr_block` | string | `10.0.0.0/16` | VPC CIDR |
| `availability_zones` | list(string) | — | 2–4 AZs |
| `single_nat_gateway` | bool | `false` | One NAT vs one per AZ |
| `enable_s3_gateway_endpoint` | bool | `true` | Free; recommended always |
| `enable_ecr_endpoints` | bool | `false` | Costs but keeps ECR pulls off NAT |
| `enable_flow_logs` | bool | `false` | Recommended for prod |
| `flow_logs_retention_days` | number | `30` | CloudWatch retention |
| `tags` | map(string) | `{}` | Extra tags merged everywhere |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | VPC id |
| `vpc_cidr_block` | Primary CIDR |
| `public_subnet_ids` / `private_subnet_ids` | Lists ordered by input AZ |
| `public_subnet_ids_by_az` / `private_subnet_ids_by_az` | Maps |
| `internet_gateway_id` | IGW id |
| `nat_gateway_ids` | List of NAT ids |
| `availability_zones` | AZs in use |

## Example

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name               = "catalog-dev"
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  single_nat_gateway = true   # dev — save the money
  enable_ecr_endpoints = false
  enable_flow_logs     = false

  tags = {
    Environment = "dev"
    Owner       = "platform"
  }
}
```

## Decisions, briefly

- **Per-AZ private route tables**: required for per-AZ NAT. Even in single-NAT
  mode we keep the per-AZ tables so flipping `single_nat_gateway = false`
  later is a no-rename, no-recreate operation.
- **`map_public_ip_on_launch = false`** on public subnets — workloads should
  live in private subnets; the public subnets only host ALB ENIs and NAT.
- **No NACLs** — security groups carry the entire allow-list. NACLs invite
  asymmetric rule pain for marginal benefit.
