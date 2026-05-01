# Module: `lambda-fn`

A Lambda function with all the production-grade trim: scoped IAM, retained
log group, optional VPC config, optional S3 event sources, optional DLQ,
optional X-Ray, optional function URL, alarms.

## What it builds

- `aws_iam_role` with an inline `logs:CreateLogStream/PutLogEvents` policy
  scoped to **this function's log group only** (not the wildcard
  `AWSLambdaBasicExecutionRole` managed policy)
- `aws_cloudwatch_log_group` with retention (so retention exists from day
  zero — without this, Lambda implicitly creates a log group with
  *infinite* retention)
- `aws_lambda_function` (zip or container image, x86_64 or arm64)
- Optional `vpc_config` + a dedicated SG when subnets are passed
- Optional `dead_letter_config` (SQS or SNS) + IAM permission to publish
- Optional `aws_lambda_function_url` (IAM-authed by default)
- Optional X-Ray tracing (with the X-Ray write policy attached)
- Per-source `aws_lambda_permission` + `aws_s3_bucket_notification` for S3
  triggers
- 3 conditional alarms: `Errors`, `Throttles`, p95 `Duration`

## Two source modes

Set exactly one:

```hcl
# zip mode
filename = "${path.module}/dist/handler.zip"
handler  = "index.handler"
runtime  = "python3.12"

# image mode
image_uri = "${module.ecr.repository_url}:${var.image_tag}"
```

The module enforces "exactly one" via a `terraform_data` precondition.

## Why a custom logs policy and not the managed one?

`AWSLambdaBasicExecutionRole` grants `logs:*` on `*`. Replacing it with an
inline policy that only allows writing to **this function's own log group**
ARN is the minimal-privilege equivalent. Combined with the pre-created log
group, this gives you a log retention enforced from day one and no
opportunity for the function role to write into other functions' streams.

## Tracing alarm threshold defaults

`duration_alarm_threshold_ms` defaults to 80% of `timeout_seconds * 1000`.
Going past it usually means the function is slowly drifting toward timeout
in production — a useful early warning before timeouts start showing up
as user-facing errors.

## VPC: opt in only

Empty `vpc_subnet_ids` (the default) keeps the function outside the VPC,
which has lower cold-start latency and cheaper ENI economics. Pass private
subnet ids when (and only when) the function needs to reach RDS or another
private resource.

## S3 trigger caveat

S3 only allows **one** `aws_s3_bucket_notification` resource per bucket. If
the same bucket is used as a source for multiple Lambda functions, manage the
notification at the env composition level instead of via this module.
The module's notification block is fine for the typical case of one bucket
→ one function.

## Inputs (highlights)

| Group | Key vars |
|---|---|
| Source | `filename` + `handler` + `runtime` *or* `image_uri` |
| Runtime | `memory_mb`, `timeout_seconds`, `ephemeral_storage_mb`, `architectures`, `environment_variables`, `tracing_mode` |
| Concurrency | `reserved_concurrent_executions` |
| IAM | `policy_arns`, `inline_policies`, `kms_key_arn` |
| VPC | `vpc_subnet_ids`, `vpc_security_group_ids` |
| Triggers | `s3_event_sources`, `create_function_url`, `function_url_auth_type` |
| Reliability | `dead_letter_target_arn`, `log_retention_days` |
| Alarms | `alarm_sns_topic_arn`, `errors_alarm_threshold`, `duration_alarm_threshold_ms` |

## Outputs

| Name | Description |
|---|---|
| `function_arn` / `invoke_arn` | For integrations (API GW uses `invoke_arn`) |
| `role_arn` / `role_name` | Attach extra policies post-hoc |
| `log_group_name` / `log_group_arn` | For dashboards / subscriptions |
| `function_url` | Public URL (null when disabled) |
| `security_group_id` | SG when in VPC |

## Example — image-resizer triggered by S3

```hcl
module "image_resizer" {
  source = "../../modules/lambda-fn"

  name        = "image-resizer-dev"
  description = "Resizes uploaded images into thumbnails"

  image_uri = "${module.resizer_ecr.repository_url}:${var.resizer_tag}"

  memory_mb       = 1024
  timeout_seconds = 60
  architectures   = ["arm64"]

  environment_variables = {
    THUMBNAIL_BUCKET = aws_s3_bucket.thumbnails.id
    THUMBNAIL_PREFIX = "thumbs/"
  }

  inline_policies = {
    s3-rw = data.aws_iam_policy_document.resizer_s3.json
  }

  s3_event_sources = {
    uploads = {
      bucket_arn    = aws_s3_bucket.uploads.arn
      events        = ["s3:ObjectCreated:*"]
      filter_prefix = "uploads/"
    }
  }

  alarm_sns_topic_arn = aws_sns_topic.alerts.arn
}
```
