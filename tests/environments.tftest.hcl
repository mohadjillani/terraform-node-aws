# The environments are compositions, so these runs plan the whole stack — four
# modules wired together — rather than one module in isolation. That is what
# catches a mis-wiring: a service pointed at the wrong subnets, or a database
# whose ingress names a security group that no longer exists.

mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/test/0123456789abcdef"
      dns_name = "test-123456789.eu-west-1.elb.amazonaws.com"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/test/0123456789abcdef"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/test"
    }
  }

  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:eu-west-1:123456789012:task-definition/test:1"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/ecs/test"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::test-assets"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:distribution/E123456789ABCD"
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:test/database-url-AbCdEf"
    }
  }
}

mock_provider "random" {}

variables {
  container_image = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/app:sha-abc"
}

run "dev_plans_end_to_end" {
  module {
    source = "./environments/dev"
  }

  assert {
    condition     = module.network.nat_gateway_count == 1
    error_message = "Dev should run one NAT gateway."
  }

  assert {
    condition     = module.network.vpc_cidr_block == "10.10.0.0/16"
    error_message = "Dev is not on its own address range."
  }

  # Every module produced something, which means the whole composition planned
  # rather than one module quietly failing to receive an input.
  assert {
    condition = alltrue([
      module.service.cluster_name != "",
      module.data.instance_identifier != "",
      module.cdn.bucket_name != "",
      length(module.network.private_subnet_ids) == 2,
    ])
    error_message = "One of the four modules did not plan."
  }
}

run "prod_plans_end_to_end" {
  module {
    source = "./environments/prod"
  }

  assert {
    condition     = module.network.nat_gateway_count == 2
    error_message = "Prod should run one NAT gateway per availability zone, or an AZ outage takes out all egress."
  }
}

run "prod_spreads_across_both_availability_zones" {
  module {
    source = "./environments/prod"
  }

  assert {
    condition = alltrue([
      length(module.network.private_subnet_ids) == 2,
      length(module.network.public_subnet_ids) == 2,
    ])
    error_message = "Prod is not spread across two availability zones."
  }

  assert {
    condition     = module.data.instance_identifier == "app-prod-db"
    error_message = "The prod database is not named for its environment."
  }
}

run "the_two_environments_use_different_address_ranges" {
  module {
    source = "./environments/prod"
  }

  # Overlapping CIDRs make the two environments impossible to peer or to
  # connect to the same VPN later, and the problem is only discovered when
  # someone tries.
  assert {
    condition     = module.network.vpc_cidr_block == "10.20.0.0/16"
    error_message = "Prod is not on its own address range."
  }
}
