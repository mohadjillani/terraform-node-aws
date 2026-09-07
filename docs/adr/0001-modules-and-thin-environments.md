# 1. Four modules, composed by environment files that hold only sizing

Status: accepted

## Context

Two shapes are common. A single root configuration with `count` and
conditionals everywhere produces a file where every resource has three
environment-specific branches and nobody can tell what prod actually looks
like. Fully separate directories per environment produce two copies that
diverge — and the day they diverge is the day testing in dev stops proving
anything about prod.

## Decision

Four modules — `network`, `service`, `data`, `cdn` — with explicit inputs and
outputs. `environments/dev` and `environments/prod` contain no resources at
all: they wire the modules together and set sizes.

The rule: if it is not a size, a count, or a protection toggle, it does not
belong in an environment file.

## Consequences

A change to how the platform works happens once, in a module, and reaches both
environments. A change to how big it is happens in one environment file and
reaches one.

The diff between `environments/dev/main.tf` and `environments/prod/main.tf` is
readable in one screen, and it is the honest answer to "how does prod differ
from dev".

`tests/environments.tftest.hcl` plans both compositions end to end, which is
what catches a mis-wiring — a service pointed at the wrong subnets, a database
whose ingress names a security group that no longer exists.

The cost is indirection: reading what prod does means opening a module. That is
the trade, and it is the right one at two environments and four modules; at one
environment it would be overhead.
