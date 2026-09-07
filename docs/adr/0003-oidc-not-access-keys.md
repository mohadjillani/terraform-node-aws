# 3. OIDC federation, not access keys in secrets

Status: accepted

## Context

CI needs AWS credentials. The path of least resistance is an IAM user with an
access key pair stored in repository secrets.

Those keys are long-lived. They are valid until someone rotates them, which
nobody does; they exist in at least two places — AWS and GitHub — and only one
of them tells you when they were last used; and anyone who can add a workflow
step can print them, or send them somewhere.

## Decision

GitHub's OIDC provider is registered in the account, and CI assumes a role by
exchanging a short-lived token. No AWS credential exists anywhere outside a
running job.

The trust policy pins both claims:

```
"token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
"token.actions.githubusercontent.com:sub" = "repo:mohadjillani/terraform-node-aws:*"
```

## Consequences

There is nothing to rotate and nothing to leak. A stolen token expires in an
hour and is bound to one repository.

**The `sub` condition is the load-bearing line.** Without it, the trust policy
says "any token from GitHub Actions", which means any workflow in any
repository anywhere can assume the role. This is the most common OIDC
misconfiguration and it is invisible until someone finds it.
`tests/bootstrap.tftest.hcl` asserts the condition is present and that changing
the repository changes the policy.

The role has `PowerUserAccess`, which is broad. Terraform creating a VPC, an
ECS service, an RDS instance and IAM roles genuinely needs a lot, and the
honest mitigation is the `sub` condition rather than a permissions list that
would be wrong within a month. A production account should narrow it to the
services in use.

The cost is a one-time setup in `bootstrap/`, and that OIDC is harder to debug
than a key: a failure is a trust-policy mismatch with a message that does not
say which claim was wrong.
