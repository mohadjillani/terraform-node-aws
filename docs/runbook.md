# Runbook

Written for the person on call, not for the person who wrote it.

## Deploy

CI does it. A merge to `main` plans both environments, then applies **the saved
plan** — the one that was reviewed — after approval on the `production`
environment.

To deploy a new image without an infrastructure change, update
`container_image` in the environment's `terraform.tfvars` and merge. CI passes
a digest rather than a tag, because a floating tag means a re-apply silently
deploys whatever `latest` points at now.

## Roll back

**The application:** re-apply with the previous image digest. ECS replaces the
tasks, and the deployment circuit breaker rolls forward automatically if the
new tasks never become healthy.

**The infrastructure:** revert the commit and let CI apply the revert. Do not
run `terraform apply` locally against prod — the state lock will stop a
concurrent CI run, but nothing stops you applying a plan nobody reviewed.

## The apply failed halfway

Terraform is not transactional. Some resources are created, some are not, and
the state reflects what actually happened.

1. Read the error. Most are permissions or a quota, not a bug in the config.
2. Run `terraform plan` again. It will show what is left to do.
3. If the state and reality disagree — a resource created but not recorded —
   `terraform import` it rather than deleting it by hand.

Do **not** delete the state file. It is the only record of what exists.

## The state is locked and nothing is running

A crashed run leaves the lock behind.

```bash
terraform force-unlock <LOCK_ID>
```

Check first that no run is actually in progress. Force-unlocking a live apply
lets a second one start against the same state, which is exactly what the lock
exists to prevent.

## Rotate the database password

The password is created by Terraform and stored in Secrets Manager. There is no
automated rotation.

1. Change the password in RDS (console or CLI).
2. Update the secret value.
3. Force a new ECS deployment so tasks pick it up:
   `aws ecs update-service --cluster app-prod --service app-prod --force-new-deployment`

The task reads the secret at start, so a rotated secret does nothing until the
tasks restart. That is a gap: a real rotation needs the application to re-read
the secret and re-open its pool.

## The service is up but returning errors

- **Logs:** `/ecs/app-prod` in CloudWatch. Retention is 90 days in prod.
- **Is it the database?** The RDS parameter group logs any statement over a
  second, which is usually the first thing to look at.
- **Is it one task?** The container health check replaces a task that is up but
  broken; if it is flapping, the ALB target group shows it.

## The database has to be restored

Backups run daily with 30 days retention in prod. Restoring creates a **new**
instance — RDS cannot restore in place.

1. Restore to a new identifier from the snapshot or a point in time.
2. Update the secret to point at the new endpoint.
3. Force a new deployment.

`prevent_destroy` on the instance means Terraform cannot be used to swap them
without removing that line deliberately, which is the point.

## Someone needs to destroy an environment

Dev, deliberately:

```bash
# prevent_destroy on the RDS instance and the assets bucket refuses this.
# Removing those lines is the deliberate act, and it belongs in a commit.
terraform -chdir=environments/dev destroy
```

Prod: no. `deletion_protection` and `prevent_destroy` are both on, and both
have to be turned off in a reviewed commit first.
