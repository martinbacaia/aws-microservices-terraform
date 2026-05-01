# Module: `ecr-repo`

ECR repository with sane defaults: scan-on-push, immutable tags, encryption,
and a lifecycle policy that prevents the repo from growing forever.

## What it builds

- `aws_ecr_repository` with `IMMUTABLE` tags and `scan_on_push = true`
- `aws_ecr_lifecycle_policy` with two rules:
  1. Keep the last N tagged images matching configured prefixes (default
     `v`, `release-`, `main-`, `sha-`)
  2. Expire **untagged** images after N days (default 7)
- Optional `aws_ecr_repository_policy` to grant pull access to extra principals

## Why immutable tags by default

Mutable tags let CI overwrite `:v1.2.3`. Combined with cached pulls in ECS,
you can end up with two tasks running different code under the same tag and
no audit trail of when it changed. Immutable forces every build to push a
unique tag (sha or semver) — if you want a moving label, that's `latest` and
nothing in prod should reference it.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Repository name |
| `image_tag_mutability` | string | `IMMUTABLE` | `MUTABLE` or `IMMUTABLE` |
| `scan_on_push` | bool | `true` | Basic vuln scan |
| `kms_key_arn` | string | `null` | Custom KMS key (else AES256) |
| `untagged_image_expiry_days` | number | `7` | Cleanup horizon for untagged |
| `max_tagged_images` | number | `30` | Retain count for tagged |
| `tagged_image_prefixes` | list(string) | `["v","release-","main-","sha-"]` | Prefixes the tagged-retention rule applies to |
| `additional_pull_principals` | list(string) | `[]` | Extra ARNs allowed to pull |
| `tags` | map(string) | `{}` | Extra tags |

## Outputs

| Name | Description |
|---|---|
| `repository_url` | What `docker push` targets |
| `repository_name` | Repository name |
| `repository_arn` | For IAM policies |

## Example

```hcl
module "products_ecr" {
  source = "../../modules/ecr-repo"

  name = "catalog-dev/products-api"
}
```
