mock_provider "aws" {}
mock_provider "random" {}

variables {
  name                       = "test"
  vpc_id                     = "vpc-123"
  private_subnet_ids         = ["subnet-a", "subnet-b"]
  allowed_security_group_ids = ["sg-tasks"]
}

run "the_database_is_not_reachable_from_the_internet" {
  module {
    source = "./modules/data"
  }

  # The single most consequential line in the module. A publicly accessible
  # database is one leaked password away from being everyone's database.
  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "The database is publicly accessible."
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted == true
    error_message = "The database is not encrypted at rest."
  }
}

run "access_is_granted_to_a_role_not_an_address_range" {
  module {
    source = "./modules/data"
  }

  # A CIDR grants access to whatever happens to be in that range later. A
  # security group reference grants it to a role.
  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.postgres : rule.cidr_ipv4 == null
    ])
    error_message = "The database security group allows an address range rather than a security group."
  }

  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.postgres :
      rule.from_port == 5432 && rule.to_port == 5432
    ])
    error_message = "The database ingress rule opens a port other than Postgres."
  }
}

run "backups_and_a_final_snapshot_cannot_be_skipped" {
  module {
    source = "./modules/data"
  }

  assert {
    condition     = aws_db_instance.this.skip_final_snapshot == false
    error_message = "The database can be destroyed without a final snapshot."
  }

  assert {
    condition     = aws_db_instance.this.backup_retention_period >= 1
    error_message = "Automated backups are disabled."
  }
}

run "backup_retention_of_zero_is_refused" {
  # `plan`, not the default `apply`: a variable validation fails during
  # planning, so an apply-stage run reports the expected failure and then fails
  # anyway for not having been able to apply.
  command = plan

  module {
    source = "./modules/data"
  }

  variables {
    backup_retention_days = 0
  }

  # AWS's own default is zero, which disables backups entirely. The variable
  # validation refuses it rather than letting a copied tfvars file create a
  # database nobody can restore.
  expect_failures = [var.backup_retention_days]
}

run "the_secret_holds_a_connection_string_not_a_password" {
  module {
    source = "./modules/data"
  }

  assert {
    condition     = can(regex("^\\$\\{|postgres://", aws_secretsmanager_secret_version.database_url.secret_string))
    error_message = "The secret should hold a full connection string, so the task needs nothing else to connect."
  }
}

run "prod_sizing_turns_on_multi_az_and_deletion_protection" {
  module {
    source = "./modules/data"
  }

  variables {
    multi_az            = true
    deletion_protection = true
    instance_class      = "db.m7g.large"
  }

  assert {
    condition     = aws_db_instance.this.multi_az == true
    error_message = "Prod should have a standby in a second availability zone."
  }

  assert {
    condition     = aws_db_instance.this.deletion_protection == true
    error_message = "Prod deletion protection is off."
  }
}
