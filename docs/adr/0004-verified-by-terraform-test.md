# 4. Verify with `terraform test` and mock providers

Status: accepted

## Context

There is no AWS account behind this repository. `terraform plan` needs
credentials; `terraform apply` needs credentials and money. `validate` catches
syntax and type errors and nothing about whether a bucket is public.

That leaves a real question: what can honestly be claimed about infrastructure
code that has never been applied?

## Decision

`terraform test` with `mock_provider`. It evaluates the real configuration, the
real module wiring and the real variable defaults, with the provider mocked, so
a full plan runs with no credentials and nothing created.

Assertions are written as **policy**, not as a snapshot of the resource graph:

- no security group allows `0.0.0.0/0` except the ALB on 80 and 443
- RDS is encrypted, not publicly accessible, and cannot skip its final snapshot
- the assets bucket blocks public access four ways
- the task role's secret ARN is specific, never `*`
- dev has one NAT gateway, prod has one per AZ
- only this repository can assume the CI role

A snapshot test would fail on every legitimate change and teach everyone to
regenerate it without reading. A policy assertion fails only when someone
breaks the rule.

## Consequences

38 assertions run in about twenty seconds on every push, with no account and no
cost. They are the reason the security claims in the README are claims rather
than hopes.

Two things this caught that no amount of reading would have:

- `for_each` over security group ids from another module cannot be planned —
  the keys are unknown until apply. It would have failed the first real apply,
  and became a `count`.
- A mocked `aws_iam_policy_document` returns a fake `json`, so any assertion
  about a policy would have been an assertion about the mock. Policies are now
  built with `jsonencode`, which Terraform evaluates itself, which makes the
  least-privilege assertions real.

**What it cannot prove**, stated plainly: that AWS accepts the configuration.
IAM policy simulation, service quotas, ACM DNS validation, whether the ECS task
actually starts — all need a real account. The modules are validated, planned
against mocks, and linted. They have never been applied.
