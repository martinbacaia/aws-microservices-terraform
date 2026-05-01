# GitHub Actions

Two workflows:

| Workflow | Trigger | What |
|---|---|---|
| `terraform-pr.yml` | PR opened/updated against `main` | Static checks (`fmt`, `validate`, `tflint`, `checkov`) + plan against `dev` posted as a PR comment |
| `terraform-apply.yml` | Manual dispatch only | Plan + apply against the selected environment, gated by the GitHub Environment's required reviewers |

## Auth: OIDC, not access keys

Both workflows authenticate to AWS via OIDC. No long-lived access keys live
in GitHub.

You need (one-time, manual):

1. Create an IAM OIDC provider for `token.actions.githubusercontent.com`.
2. Create an IAM role per environment with a trust policy restricted to your
   repo and (optionally) branch:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<acct>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:<owner>/<repo>:environment:dev" }
    }
  }]
}
```

3. Attach a policy that allows the actions Terraform performs (start strict,
   widen as needed). For PR plans you only need read-ish APIs + state bucket
   access; for apply you need the full set.

## Repository variables (Settings → Secrets and variables → Actions → Variables)

| Name | Value |
|---|---|
| `AWS_ROLE_TO_ASSUME` | ARN of the IAM role to assume |
| `TF_STATE_BUCKET` | Output of `bootstrap` (`state_bucket_name`) |
| `TF_STATE_KMS_KEY` | Output of `bootstrap` (`kms_key_arn` or its alias) |
| `TF_LOCK_TABLE` | Output of `bootstrap` (`lock_table_name`) |

The PR workflow skips the plan step automatically when `AWS_ROLE_TO_ASSUME`
is empty, so the static checks still pass on a fresh fork.

## GitHub Environments → required reviewers

In Settings → Environments, create `dev`, `staging`, `prod` and add required
reviewers on `staging` and `prod`. The `terraform-apply.yml` workflow's
`environment:` block will pause until a reviewer approves.

This is "no auto-apply on merge" enforced by the GitHub gate, **not** by
Terraform.
