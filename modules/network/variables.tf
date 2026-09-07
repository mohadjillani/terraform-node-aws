variable "name" {
  description = "Prefix for every resource name, usually the environment."
  type        = string
}

variable "cidr_block" {
  description = "The VPC's address range."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid CIDR, e.g. 10.0.0.0/16."
  }
}

variable "availability_zones" {
  description = "AZs to spread subnets across. Two is the minimum for an ALB."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "An ALB requires subnets in at least two availability zones."
  }
}

variable "nat_gateway_count" {
  description = <<-EOT
    How many NAT gateways to run.

    One is a single point of failure and costs a fraction of the alternative;
    one per AZ survives an AZ outage. Dev uses one, prod uses one per AZ, and
    the difference is most of the gap in the cost table.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.nat_gateway_count >= 1
    error_message = "Private subnets need at least one NAT gateway for egress."
  }
}

variable "enable_interface_endpoints" {
  description = <<-EOT
    Interface endpoints for ECR, CloudWatch Logs and Secrets Manager.

    They take image pulls and log shipping off the NAT gateway's per-gigabyte
    charge — and they are billed per endpoint per availability zone, which for
    four endpoints across two AZs is eight hourly charges.

    The generated cost table decided this default: in a low-traffic dev
    environment the endpoints cost more than the NAT egress they save, so dev
    turns them off and prod leaves them on. Check `docs/cost.md` against your
    own traffic rather than copying the answer.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
