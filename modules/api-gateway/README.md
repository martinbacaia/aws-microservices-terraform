# Module: `api-gateway`

HTTP API (API Gateway v2) with Lambda integrations, CORS, optional JWT
authorizers, throttling, JSON access logs, and alarms.

## What it builds

- `aws_apigatewayv2_api` (HTTP, with optional CORS configuration — preflight
  handled by API Gateway, no Lambda invocation for OPTIONS)
- `aws_apigatewayv2_stage` with `auto_deploy = true`, default-route
  throttling, JSON access logs to CloudWatch
- `aws_cloudwatch_log_group` for access logs (with retention)
- `aws_apigatewayv2_integration` per Lambda (AWS_PROXY, payload format 2.0)
- `aws_lambda_permission` per Lambda, scoped to **this API's execution
  ARN** (no `*` source ARN)
- `aws_apigatewayv2_authorizer` per JWT issuer (optional)
- `aws_apigatewayv2_route` per `route_key`, with preconditions enforcing
  that the integration and authorizer references resolve
- 3 conditional alarms: 5xx count, 4xx-to-total ratio (using
  `metric_query` IF expression), p95 integration latency

## How the maps fit together

The module is driven by three maps that compose:

```
lambda_integrations   →  aws_apigatewayv2_integration
        ↑                       ↑
        │      routes ──────────┘
        │
       referenced by routes[*].integration
```

```hcl
module "api" {
  source = "../../modules/api-gateway"

  name = "catalog-dev"

  lambda_integrations = {
    resizer = {
      function_name = module.image_resizer.function_name
      invoke_arn    = module.image_resizer.invoke_arn
    }
    products = {
      function_name = module.products_lambda.function_name
      invoke_arn    = module.products_lambda.invoke_arn
    }
  }

  routes = {
    "POST /thumbnails"   = { integration = "resizer" }
    "GET /products"      = { integration = "products" }
    "GET /products/{id}" = { integration = "products" }
    "$default"           = { integration = "products" } # catch-all
  }

  cors_configuration = {
    allow_origins = ["https://app.dev.example.com"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
    max_age       = 300
  }

  alarm_sns_topic_arn = aws_sns_topic.alerts.arn
}
```

## JWT auth

```hcl
jwt_authorizers = {
  cognito = {
    issuer   = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_ABC123"
    audience = ["myapp-web-client-id"]
  }
}

routes = {
  "POST /products" = {
    integration        = "products"
    authorization_type = "JWT"
    authorizer_key     = "cognito"
  }
}
```

The route precondition refuses to apply if `authorizer_key` does not exist
in `jwt_authorizers`, or if `integration` does not exist in
`lambda_integrations` — typos fail at plan time, not runtime.

## CORS gotcha worth knowing

When `cors_configuration` is set, API Gateway answers OPTIONS preflight on
its own and **never invokes your Lambda** for it. That is the right
behaviour but trips people up: if you want to handle CORS in the function
itself (advanced cases), pass `cors_configuration = null` and add an
explicit OPTIONS route.

## Throttling

`default_route_throttling_*` apply to every route via the stage's
`default_route_settings`. Per-route overrides are not exposed by this
module (rare in practice; add via a follow-up resource if needed).

## Inputs (selected — full list in `variables.tf`)

| Group | Vars |
|---|---|
| Identity | `name`, `description`, `stage_name` |
| Wiring | `lambda_integrations`, `routes`, `jwt_authorizers` |
| Behaviour | `cors_configuration`, `default_route_throttling_burst_limit/rate_limit` |
| Logs | `access_log_retention_days`, `kms_key_arn` |
| Alarms | `alarm_sns_topic_arn`, `alarm_5xx_threshold`, `alarm_4xx_ratio_threshold`, `alarm_latency_p95_ms` |

## Outputs

| Name | Description |
|---|---|
| `api_id` / `api_arn` | The API |
| `api_endpoint` / `invoke_url` | What clients hit |
| `execution_arn` | Use as prefix when adding Lambda permissions outside this module |
| `stage_name` | Stage name |
| `access_log_group_name` | For dashboards / Logs Insights |
| `integration_ids` | Useful for adding routes outside the module |

## Decisions

- **HTTP API, not REST** — cheaper, simpler, JWT built in. The repo's use
  case (Lambda invocation, no usage plans / API keys) does not need REST.
- **`payload_format_version = "2.0"` default** — flatter event shape, less
  glue code in the Lambda handler.
- **Access logs as JSON** — queryable in Logs Insights without parsing.
- **No custom domain in this module** — listed in "What I'd add for real
  prod" in the root README; ACM cert + Route 53 alias + `aws_apigatewayv2_domain_name`
  is straightforward to bolt on.
