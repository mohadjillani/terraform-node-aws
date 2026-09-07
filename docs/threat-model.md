# Threat model

What an attacker reaches from where, and what stops them.

## The attack surface

Exactly one thing in this VPC is reachable from the internet: the load
balancer, on 80 and 443. Everything else — tasks, database, endpoints — accepts
traffic only from a named security group.

```
internet ──443──▶ ALB ──3000──▶ tasks ──5432──▶ RDS
                   │              │
              (public subnets) (private subnets, no public IP)
```

`tests/service.tftest.hcl` asserts this rather than describing it: the task
security group's ingress rule must reference a security group, not a CIDR, and
the ALB's rules must open only 80 and 443.

## If an attacker gets code execution in a container

This is the scenario worth designing for, because a dependency compromise is
the likeliest way in.

**What they get.** The task role, which has no permissions at all — every one
should be something a person had to argue for. `DATABASE_URL`, because the
container needs it. Network egress to anywhere, because the application calls
third parties.

**What they do not get.** Any other secret in the account: the *execution* role
names one secret ARN, and `secretsmanager:*` on `*` is asserted against in the
tests. The ability to reach another environment: dev and prod are separate
VPCs on separate address ranges. Anything on the host: Fargate has no host to
reach.

**What is still exposed.** The database, completely — the credentials are in
the container by necessity. Mitigations that are *not* implemented here and
would be the next step: a read-only role for the paths that only read, and
IAM database authentication so the credential is short-lived rather than a
password.

## If an attacker gets the state file

The state contains every resource id, every output, and the database password
in plain text — Terraform state is not encrypted at the value level, whatever
the backend does. The bucket therefore blocks all public access, is versioned,
and is encrypted at rest, and `tests/bootstrap.tftest.hcl` asserts it.

Anyone with read access to that bucket has the database password. That is a
property of Terraform, not of this repository, and the honest mitigation is to
treat state bucket access as equivalent to production database access.

## If an attacker can open a pull request

They cannot make CI apply anything. The plan job runs on a pull request and
uploads a plan artifact; the apply job runs only on a push to `main`, behind a
GitHub environment that requires approval.

The OIDC trust policy names this repository in its `sub` condition. Without
that condition — the single most common OIDC misconfiguration — any GitHub
Actions workflow in the world could assume the role. There is a test for it.

## What is deliberately not addressed

**No WAF.** An ALB with no WAF in front of it is exposed to the application-
layer attacks the application itself has to handle. A WAF is worth adding and
is a decision with its own cost and false-positive rate.

**Egress is open.** The task can reach anything outbound, which is how
exfiltration works. Locking it down needs a list of every outbound dependency —
a real project, not a line in a module.

**No secret rotation.** The database password is created once. Rotation needs a
Lambda and a rotation schedule, and doing it badly locks the application out of
its own database.

**No GuardDuty, no CloudTrail, no Config.** Detection is absent. This
repository is about what is provisioned, not about watching it.
