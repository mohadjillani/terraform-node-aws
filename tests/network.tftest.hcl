# Verified with mock providers, never against an AWS account.
#
# `terraform test` evaluates the real configuration, the real module wiring and
# the real variable defaults; the provider is mocked, so nothing is created and
# no credentials are needed. Assertions are written as policy — "no private
# subnet has a route to the internet gateway" — rather than as a snapshot of the
# resource graph, because a snapshot fails on every legitimate change and
# teaches everyone to regenerate it without reading.

mock_provider "aws" {}

variables {
  name               = "test"
  availability_zones = ["eu-west-1a", "eu-west-1b"]
  tags               = { Environment = "test" }
}

run "subnets_span_every_availability_zone" {
  module {
    source = "./modules/network"
  }

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2
    error_message = "Expected one public and one private subnet per availability zone."
  }

  assert {
    condition = alltrue([
      for index, subnet in aws_subnet.public : subnet.availability_zone == var.availability_zones[index]
    ])
    error_message = "Public subnets are not spread across the given availability zones."
  }
}

run "subnet_ranges_do_not_overlap" {
  module {
    source = "./modules/network"
  }

  assert {
    condition = length(distinct(concat(
      aws_subnet.public[*].cidr_block,
      aws_subnet.private[*].cidr_block
    ))) == 4
    error_message = "Two subnets were given the same address range."
  }
}

run "public_subnets_do_not_auto_assign_addresses" {
  module {
    source = "./modules/network"
  }

  assert {
    condition     = alltrue([for subnet in aws_subnet.public : subnet.map_public_ip_on_launch == false])
    error_message = "A public subnet auto-assigns public addresses; only the load balancer should be reachable."
  }
}

# The assertion that matters most in this module. A private subnet routed to the
# internet gateway is a private subnet in name only, and it is a one-line
# mistake that nothing else catches.
run "private_subnets_have_no_route_to_the_internet_gateway" {
  module {
    source = "./modules/network"
  }

  assert {
    condition     = alltrue([for route in aws_route.private_nat : route.gateway_id == null])
    error_message = "A private subnet routes to the internet gateway."
  }

  assert {
    condition     = length(aws_route.private_nat) == 2
    error_message = "Every private subnet needs a default route, or its tasks cannot reach anything."
  }
}

run "dev_runs_one_nat_gateway" {
  module {
    source = "./modules/network"
  }

  variables {
    nat_gateway_count = 1
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "Dev should share one NAT gateway; it is the largest line in the dev cost table."
  }

  # Both private route tables point at the single gateway, which is what makes
  # one NAT work at all.
  assert {
    condition     = length(distinct(aws_route.private_nat[*].nat_gateway_id)) == 1
    error_message = "With one NAT gateway, every private route table should point at it."
  }
}

run "prod_runs_one_nat_gateway_per_availability_zone" {
  module {
    source = "./modules/network"
  }

  variables {
    nat_gateway_count = 2
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "Prod should not lose egress in every AZ when one AZ fails."
  }

  assert {
    condition     = length(distinct(aws_route.private_nat[*].nat_gateway_id)) == 2
    error_message = "Each private route table should use its own AZ's NAT gateway."
  }
}

run "s3_reaches_its_endpoint_without_the_nat_gateway" {
  module {
    source = "./modules/network"
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3.route_table_ids) == 2
    error_message = "The S3 gateway endpoint must be attached to every private route table, or object traffic pays NAT charges."
  }
}

run "endpoint_security_group_is_closed_to_the_internet" {
  module {
    source = "./modules/network"
  }

  assert {
    condition = alltrue(flatten([
      for group in aws_security_group.endpoints : [
        for rule in group.ingress : !contains(rule.cidr_blocks, "0.0.0.0/0")
      ]
    ]))
    error_message = "The VPC endpoint security group is open to the internet."
  }
}

# The S3 gateway endpoint is free and stays on regardless; the interface
# endpoints are billed per AZ and are the ones the cost table argued about.
run "interface_endpoints_can_be_turned_off_without_losing_the_s3_endpoint" {
  module {
    source = "./modules/network"
  }

  variables {
    enable_interface_endpoints = false
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0
    error_message = "Interface endpoints were created when they were disabled."
  }

  assert {
    condition     = length(aws_security_group.endpoints) == 0
    error_message = "The endpoint security group is left behind when the endpoints are gone."
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3.route_table_ids) == 2
    error_message = "The free S3 gateway endpoint should not be affected."
  }
}
