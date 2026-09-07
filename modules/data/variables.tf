variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "The database lives here. Never in a public subnet."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = <<-EOT
    Security groups allowed to reach the database.

    A list of groups rather than a CIDR: an address range grants access to
    anything that happens to be in it later, and "the private subnets" grows
    over time. A security group reference grants access to a role.
  EOT
  type        = list(string)
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  type    = number
  default = 20
}

variable "engine_version" {
  type    = string
  default = "16.4"
}

variable "multi_az" {
  description = "A standby in a second AZ. Roughly doubles the cost, and is the difference between a failover and an outage."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  type    = number
  default = 7

  validation {
    # Zero disables automated backups entirely, and it is the default AWS
    # offers. A database with no backups is not a database anyone should have
    # to reason about, so the module refuses to create one.
    condition     = var.backup_retention_days >= 1
    error_message = "Backup retention must be at least one day; zero disables backups entirely."
  }
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
