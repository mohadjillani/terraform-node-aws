# The same four modules as dev. The only differences are sizes, redundancy and
# the two protections — which is the property tests/environments.tftest.hcl
# asserts, because an environment pair that has quietly diverged is one where
# testing in dev proves nothing about prod.

locals {
  name = "app-prod"

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Repository  = "mohadjillani/terraform-node-aws"
  }
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  cidr_block         = "10.20.0.0/16"
  availability_zones = var.availability_zones

  # One per AZ. An AZ outage then costs half the capacity rather than all of
  # the egress.
  nat_gateway_count = 2

  tags = local.tags
}

module "data" {
  source = "../../modules/data"

  name                       = local.name
  vpc_id                     = module.network.vpc_id
  private_subnet_ids         = module.network.private_subnet_ids
  allowed_security_group_ids = [module.service.task_security_group_id]

  instance_class       = "db.m7g.large"
  allocated_storage_gb = 100
  multi_az             = true

  backup_retention_days = 30
  deletion_protection   = true

  tags = local.tags
}

module "service" {
  source = "../../modules/service"

  name               = local.name
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids

  container_image     = var.container_image
  database_secret_arn = module.data.secret_arn

  desired_count = 3
  cpu           = 1024
  memory        = 2048
  min_capacity  = 3
  max_capacity  = 20

  log_retention_days = 90
  certificate_arn    = var.certificate_arn

  tags = local.tags
}

module "cdn" {
  source = "../../modules/cdn"

  name        = local.name
  price_class = "PriceClass_All"

  tags = local.tags
}
