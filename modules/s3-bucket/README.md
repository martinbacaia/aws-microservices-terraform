# Module: `s3-bucket`

Hardened S3 bucket — the six boilerplate resources every "secure bucket"
needs, behind one module call.

## What it builds

- `aws_s3_bucket` (with optional `force_destroy`)
- `aws_s3_bucket_versioning` (enabled by default)
- `aws_s3_bucket_server_side_encryption_configuration` — AES256 default,
  CMK if `sse_algorithm = "aws:kms"` and `kms_key_arn` set (precondition
  enforces the pair)
- `aws_s3_bucket_public_access_block` (all four flags on by default)
- `aws_s3_bucket_ownership_controls` (`BucketOwnerEnforced`)
- `aws_s3_bucket_lifecycle_configuration` (single rule, optional) covering
  expiration, noncurrent expiration, and incomplete multipart cleanup
- `aws_s3_bucket_policy` — TLS-only deny by default; pass `policy_json` to
  override completely

## Why a module?

Every bucket in the rest of this repo (`uploads`, `thumbnails`, `alb-logs`,
the bootstrap state bucket) wants the same six resources. Inline they total
~50 lines per bucket × N buckets × M environments = a lot of noise that
hides the actual differences.

## Inputs (selected)

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Globally unique bucket name |
| `versioning_enabled` | bool | `true` | Enable versioning |
| `sse_algorithm` | string | `AES256` | `AES256` or `aws:kms` |
| `kms_key_arn` | string | `null` | Required when KMS |
| `block_public_access` | bool | `true` | All four flags |
| `force_destroy` | bool | `false` | Always false for data buckets |
| `expiration_days` | number | `null` | Delete current versions after N days |
| `noncurrent_version_expiration_days` | number | `null` | Delete overwritten versions |
| `abort_incomplete_multipart_days` | number | `7` | Multipart cleanup |
| `policy_json` | string | `null` | Custom policy (overrides TLS-only default) |
| `deny_insecure_transport` | bool | `true` | Install the TLS deny when `policy_json` is null |
| `tags` | map(string) | `{}` | Extra tags |

## Outputs

| Name | Description |
|---|---|
| `id` | Bucket name |
| `arn` | Bucket ARN |
| `regional_domain_name` | For virtual-hosted-style URLs |
| `tls_only_statement_json` | Helper — embed in custom policies |

## Examples

### Plain hardened bucket

```hcl
module "uploads" {
  source = "../../modules/s3-bucket"

  name                               = "${local.name}-uploads-${random_id.suffix.hex}"
  noncurrent_version_expiration_days = 30
}
```

### ALB logs bucket — needs custom policy

The ELB log delivery service principal needs `PutObject` on the bucket. The
module's TLS-only default would not allow that, so we pass a full
`policy_json` and include the TLS-only statement ourselves.

```hcl
data "aws_iam_policy_document" "alb_logs" {
  source_policy_documents = [module.alb_logs.tls_only_statement_json]

  statement {
    sid       = "AWSLogDeliveryWrite"
    actions   = ["s3:PutObject"]
    resources = ["${module.alb_logs.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }
  # ... other statements
}

module "alb_logs" {
  source = "../../modules/s3-bucket"

  name            = "${local.name}-alb-logs-${random_id.suffix.hex}"
  expiration_days = 90

  # Bucket policy is supplied separately (chicken-and-egg with the bucket arn)
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = module.alb_logs.id
  policy = data.aws_iam_policy_document.alb_logs.json
}
```

In practice, attaching the policy from outside the module is cleaner when
the policy needs the bucket ARN — Terraform's module-input ordering does
not hand the caller the ARN until after the module is built. Pass
`deny_insecure_transport = false` to the module if you do this.
