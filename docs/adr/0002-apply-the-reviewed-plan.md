# 2. Apply the saved plan, never a fresh one

Status: accepted

## Context

The usual pipeline runs `terraform plan` on a pull request so a human can read
it, then runs `terraform apply` on merge. Those are two different plans.

Between them, anything can change: another apply, a manual console edit, a
resource that drifted, a data source whose value moved. The apply does whatever
is true at the moment it runs, which may not be what anyone approved. The
review was of a document that no longer describes what is about to happen.

## Decision

The plan job writes `terraform plan -out=tfplan` and uploads the file. The
apply job downloads that artifact and runs `terraform apply tfplan`. The plan
that was reviewed is the plan that is applied, or the apply fails because the
state moved underneath it.

## Consequences

A review means something. If the world changed since the plan was made,
Terraform refuses the stale plan rather than applying something new — which is
the correct failure and is loud.

The state lock in DynamoDB is the other half. Without it, two workflow runs
starting seconds apart both plan against the same state and the second
overwrites the first. The lock table is created by `bootstrap/`, which cannot
itself live in the state it stores.

The cost is that a stale plan has to be regenerated, which is a re-run rather
than a mystery. And the artifact contains the full plan, including any values
Terraform does not mark sensitive — so its retention is short and the
repository is private in any real use.
