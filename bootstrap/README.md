# Backend bootstrap

One-shot stack that provisions the **S3 bucket + DynamoDB table** that every
other environment uses for remote state and state locking.

## Why a separate stack?

You can't store the state of the bucket that holds your state inside that same
bucket. This stack is the only piece of the repo that runs against a **local**
state file — once it has run, every other stack uses the resources it created
as a remote backend.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_s3_bucket` (versioned, KMS-encrypted, TLS-only, public-access blocked) | Holds `*.tfstate` for all envs |
| `aws_kms_key` + alias | CMK encrypting state at rest, with rotation |
| `aws_s3_bucket_lifecycle_configuration` | Expires noncurrent versions after 365 days |
| `aws_dynamodb_table` (PAY_PER_REQUEST, PITR, SSE) | State locking |

## Usage

```bash
cd bootstrap
cp example.tfvars terraform.tfvars
# edit terraform.tfvars — bucket name MUST be globally unique
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Then capture the outputs and drop them into each environment's `backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "tfstate-aws-microservices-<your-suffix>"
    key            = "envs/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
    kms_key_id     = "alias/tfstate-aws-microservices-<your-suffix>"
  }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `region` | string | `us-east-1` | Region for the bucket and lock table |
| `state_bucket_name` | string | — | Globally unique bucket name |
| `lock_table_name` | string | `terraform-state-locks` | DynamoDB lock table name |
| `force_destroy` | bool | `false` | Allow `terraform destroy` to delete a non-empty bucket. Leave false. |

## Outputs

| Name | Description |
|---|---|
| `state_bucket_name` | Bucket name to put in `backend.tf` |
| `state_bucket_arn` | For IAM policies granting CI access |
| `lock_table_name` | DynamoDB table name for `dynamodb_table` |
| `kms_key_arn` | CI roles must `kms:Decrypt` this key |
| `region` | Backend region |

## Tear down

The bucket has `force_destroy = false` by default to prevent accidental state
loss. To intentionally delete:

1. Empty all environments' state objects manually after `terraform destroy` of
   each env.
2. Re-run this stack with `-var=force_destroy=true` then `terraform destroy`.
