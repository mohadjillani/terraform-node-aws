resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.private_subnet_ids
  tags       = merge(var.tags, { Name = "${var.name}-db" })
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Postgres, reachable only from the application"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-db" })
}

# A separate rule resource per source group rather than inline ingress blocks:
# inline blocks are replaced wholesale on every change, which briefly removes
# access for every other source during an apply.
#
# `count`, not `for_each`. The security group ids come from another module and
# are unknown until that module is applied, and `for_each` needs its keys at
# plan time — so `for_each` here fails the very first apply with "the for_each
# value depends on resource attributes that cannot be determined until apply".
# The environment tests caught it before an account ever would have.
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Postgres from the application"
}

resource "random_password" "master" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "database_url" {
  name        = "${var.name}/database-url"
  description = "Connection string for ${var.name}, read by the ECS task role"
  tags        = var.tags

  # Long enough to recover from an accidental delete, short enough that a
  # rotated secret does not linger for a month.
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id = aws_secretsmanager_secret.database_url.id
  secret_string = format(
    "postgres://%s:%s@%s:%s/%s",
    aws_db_instance.this.username,
    random_password.master.result,
    aws_db_instance.this.address,
    aws_db_instance.this.port,
    aws_db_instance.this.db_name,
  )
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-pg16"
  family = "postgres16"

  # Log anything slower than a second. The default logs nothing, and the first
  # thing anyone wants during an incident is the slow query log.
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  tags = var.tags
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = "app"
  username = "appadmin"
  password = random_password.master.result

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.allocated_storage_gb * 4
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.this.name

  # The single most consequential line in this module. A publicly accessible
  # database is one leaked password away from being everyone's database.
  publicly_accessible = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:30-sun:05:30"

  # A final snapshot on delete, always. `skip_final_snapshot = true` is the
  # default in most examples and it is how a database is destroyed with no way
  # back.
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-db-final"

  deletion_protection = var.deletion_protection

  auto_minor_version_upgrade      = true
  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(var.tags, { Name = "${var.name}-db" })

  lifecycle {
    # Terraform must not be able to destroy the database, whatever the plan
    # says. Removing this line is a deliberate act with a review attached.
    prevent_destroy = true

    # The password lives in the secret; a change here would force a replacement
    # of the instance.
    ignore_changes = [password]
  }
}
