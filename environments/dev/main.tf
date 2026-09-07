# A composition file. Everything here is wiring and sizing — no resources, so a
# change to how the platform works happens in a module and reaches both
# environments, and a change to how big it is happens here and reaches one.

locals {
  name = "app-dev"

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
    Repository  = "mohadjillani/terraform-node-aws"
  }
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  cidr_block         = "10.10.0.0/16"
  availability_zones = var.availability_zones

  # One shared NAT gateway. It is a single point of failure and it is most of
  # the difference between the dev and prod bills — an acceptable trade for an
  # environment whose downtime costs nothing.
  nat_gateway_count = 1

  tags = local.tags
}

module "data" {
  source = "../../modules/data"

  name                       = local.name
  vpc_id                     = module.network.vpc_id
  private_subnet_ids         = module.network.private_subnet_ids
  allowed_security_group_ids = [module.service.task_security_group_id]

  instance_class       = "db.t4g.micro"
  allocated_storage_gb = 20
  multi_az             = false

  # Short, but not zero — the module refuses zero.
  backup_retention_days = 1
  # Off in dev, so a `terraform destroy` of the environment can succeed. The
  # `prevent_destroy` lifecycle rule in the module still refuses it, which is
  # the reminder to be deliberate.
  deletion_protection = false

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

  desired_count = 1
  cpu           = 256
  memory        = 512
  min_capacity  = 1
  max_capacity  = 3

  log_retention_days = 7
  certificate_arn    = var.certificate_arn

  tags = local.tags
}

module "cdn" {
  source = "../../modules/cdn"

  name        = local.name
  price_class = "PriceClass_100"

  tags = local.tags
}
