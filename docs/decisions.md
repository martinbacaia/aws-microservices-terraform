# Architecture decision log

The condensed table is in the root README. This file is the longer form:
the alternatives considered, why the chosen option won, and what would
flip the decision.

---

## ADR-001 — Compute platform: ECS Fargate

**Decision.** Use ECS Fargate for long-running containerised services.

**Alternatives considered.**
- **EKS / Kubernetes.** Standard orchestration, larger ecosystem, but
  significant operational overhead: control-plane upgrades, node group
  patching, cluster autoscaler, IRSA, etc. For a two-service workload it
  is not justifiable.
- **EC2 + ECS classic.** Cheaper per vCPU at scale; but you own the AMIs,
  patching, capacity scaling. The "boring infrastructure" tax is real.
- **App Runner.** Easier than Fargate for a single service, but limited
  networking (no private VPC integration without recent updates) and you
  give up control over task shape.

**Why Fargate.**
- Per-task IAM (`task_role`) and per-task networking (`awsvpc`) without
  any node-level concerns.
- Container Insights is a checkbox.
- Capacity provider strategy lets you mix on-demand and spot trivially.

**What would flip this.** A platform team supporting >5–10 services with
diverse runtimes would amortise EKS's overhead. Below that threshold, the
math points at Fargate.

---

## ADR-002 — Image resizer on Lambda, not ECS

**Decision.** Run the resizer as a Lambda triggered by S3 events, with API
Gateway as a secondary entrypoint.

**Why.**
- Bursty, S3-event-driven, embarrassingly parallel — the canonical Lambda
  shape.
- Sub-15-minute runtime per invocation by definition (image resize).
- No always-on cost when there are no uploads.

**Alternatives.**
- **ECS** — would need autoscaling on a queue depth metric and you pay for
  idle tasks. Wins only if the image processing exceeds 15 minutes (it
  doesn't) or if you need custom system libraries the Lambda runtime
  doesn't ship (containerised Lambda solves that).
- **Step Functions + Lambda** — overkill for a single-step transformation.
  Worth it if resizing fans out into multiple sizes or compositions.

**Container image vs zip.** The composition uses container Lambda, so the
same ECR repo + image build pipeline that produces other services works
here. Zip mode is supported by the module — switch by setting `filename`
+ `handler` + `runtime` instead of `image_uri`.

---

## ADR-003 — Database: RDS Postgres, not DynamoDB

**Decision.** RDS Postgres single-instance for dev, Multi-AZ for staging /
prod.

**Why not DynamoDB.** DynamoDB is the right answer when access patterns
are well-known and key-driven. A product catalog has relational query
shapes (search by category and price range, joins between products and
inventory) that fit Postgres better. Trying to model these in DynamoDB
forces denormalisation and adapter code that gives DynamoDB's flexibility
without its strengths.

**Why not Aurora.** Aurora Serverless v2 is a real option for staging /
prod and the modules would need ~30 lines of work to support it. The
trade-off is cost: Aurora is meaningfully pricier at the RDS instance
sizes here. The decision was: pick the simpler thing first; switch to
Aurora when scaling reasons (read replicas with quick failover, storage
auto-scaling beyond 500 GiB) actually arrive.

---

## ADR-004 — Edge: ALB for ECS, API Gateway for Lambda

**Decision.** Use ALB for the ECS service, API Gateway HTTP API for the
Lambda.

**Why split.**
- **ALB** is the right shape for HTTP services that need persistent
  connections, host/path-based routing across many services, low latency
  per request, and predictable LCU pricing.
- **API Gateway HTTP API** is the right shape for Lambda: throttling,
  CORS, JWT auth all built-in; no need to write handler code for any of
  it; pay-per-request pricing matches the Lambda model.

**Why not API Gateway in front of ECS too.** Doable via VPC Link, but adds
a hop, latency, and per-request cost on top of the ALB you already need.
The use case doesn't benefit.

**Why not ALB in front of Lambda too.** ALB → Lambda integration exists
and works, but you lose API Gateway's stage variables, throttling per
route, JWT authorizer, and the JSON access logs.

---

## ADR-005 — Networking: per-AZ NAT in prod, single NAT in dev

**Decision.** `single_nat_gateway = true` in dev only.

**Numbers.** A NAT Gateway is roughly **$32/month** plus data processing
(~$0.045/GB). Three AZs of NAT therefore costs ~$96/month + data, vs ~$32
+ data for one. In dev this is half of the bill; in prod, it's a rounding
error compared to the cost of an AZ-wide outage cutting all private-subnet
egress.

**Per-AZ private route tables in both modes.** Even in single-NAT mode the
module creates one route table per AZ. Flipping `single_nat_gateway` to
`false` later changes only the route target — no rename, no recreate, no
downtime.

---

## ADR-006 — Two IAM roles per ECS task

**Decision.** Distinct **execution role** and **task role** per service.

**Execution role.** Pulls images from ECR, writes to its own log group,
fetches the secrets that this task declares (`secret_arns` in the
module). Scoped tightly: `secretsmanager:GetSecretValue` only on the ARNs
in `var.secret_arns`, not `*`.

**Task role.** What the application itself can do. Caller passes
`task_role_policy_arns` and/or `task_role_inline_policies`.

**Why split.** The execution role is assumed by the ECS agent
out-of-band of your code. The task role is assumed via the task metadata
endpoint by the application. Mixing them widens both unnecessarily — and
makes "what can my app do?" harder to answer.

---

## ADR-007 — Secrets in Secrets Manager, generated by Terraform, ignored on rotation

**Decision.** The RDS master password is generated by `random_password`
inside the module, written to a Secrets Manager secret, and the function
has `lifecycle { ignore_changes = [password] }` on the DB instance.

**Why.**
- The password never appears in `tfvars` (which would commit it).
- State is encrypted at rest in the bootstrap-managed S3 bucket with KMS.
- `ignore_changes` lets Secrets Manager rotation Lambdas update the
  password later without `terraform apply` clobbering the change.

**Alternative considered.** External secret generation + import.
Rejected because it adds a manual setup step and an "out-of-band" source
of truth that's easy to forget.

---

## ADR-008 — Remote state: S3 + DynamoDB + KMS, bootstrapped separately

**Decision.** Backend resources (state bucket, lock table, KMS key) live in
a dedicated `bootstrap/` stack with **local state**. Every other stack
points its `backend.tf` at those resources for **remote state**.

**Why local state for bootstrap.** Chicken-and-egg: you can't store the
state of the bucket that holds your state inside that same bucket. The
bootstrap stack is small, run-once, and its local state file can be
checked into a private/locked-down location or destroyed after first
apply (the resources will not change).

**Hardening on the state bucket.**
- Versioning (state corruption recovery).
- KMS-CMK SSE with rotation (auditable via CloudTrail).
- Public access block + ownership=BucketOwnerEnforced.
- TLS-only bucket policy (`Deny aws:SecureTransport=false`).
- Lifecycle: noncurrent versions expire at 365d.
- DynamoDB: PAY_PER_REQUEST + PITR + SSE.

---

## ADR-009 — CI: plan-on-PR, manual apply, OIDC auth

**Decision.** PRs run static checks + `terraform plan` against `dev` and
post the diff as a sticky comment. Apply is `workflow_dispatch` only,
gated by GitHub Environments required reviewers, with OIDC auth to AWS.

**Why no auto-apply on main.** Human approval before infrastructure
changes is the cheapest insurance against rollouts that pass CI but
shouldn't have. The cost is one click on dispatch; the benefit is the
ability to look at the plan one more time and pause if something looks
off.

**Why OIDC.** Long-lived AWS access keys in GitHub secrets are an exfil
risk. The OIDC trust policy can be scoped to the exact repo + branch +
environment combination.

---

## ADR-010 — Module boundaries: each module owns its scope, nothing else

**Examples.**
- The `alb` module creates the ALB and its listeners but **not** target
  groups. Target groups belong to the service that owns the workload —
  the `ecs-service` module attaches its own. One ALB → N services without
  the ALB module knowing about any of them.
- The `api-gateway` module wires routes to integrations but **does not
  create the Lambda functions**. Functions are created by the `lambda-fn`
  module and passed in by ARN.
- The `ecs-service` module creates a cluster only if `cluster_arn` is
  null. Pass an existing cluster to share it across services.

**Why this matters.** It's the difference between a module library that
composes and a module that's "almost what you need" until your fifth
service. Clear ownership boundaries are the unsexy heart of a healthy IaC
codebase.

---

## ADR-011 — What we did NOT do (yet)

Listed in the root README under "What I'd add for real prod". The short
version: WAF, custom domains, blue/green deploys, app autoscaling,
secrets rotation, multi-region, Cognito JWT, Config/GuardDuty,
backup-vault cross-region copies, cost-anomaly detection, terratest, OPA.
None of these are hard to bolt on; they're omitted because the goal was
a focused reference rather than a "kitchen sink" demo where the signal
gets lost in optionality.
