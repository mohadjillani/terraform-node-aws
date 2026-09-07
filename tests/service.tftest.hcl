# The AWS provider validates ARN-shaped attributes even under a mock, and a
# mocked resource's computed `arn` is otherwise a random string. These defaults
# give the mocks the shape the provider insists on; nothing here is asserted
# against, so they cannot make a test pass that should fail.
mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/test/0123456789abcdef"
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
}

variables {
  name                = "test"
  vpc_id              = "vpc-123"
  public_subnet_ids   = ["subnet-pub-a", "subnet-pub-b"]
  private_subnet_ids  = ["subnet-priv-a", "subnet-priv-b"]
  container_image     = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/app:sha-abc123"
  database_secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:test/database-url-AbCdEf"
}

run "only_the_load_balancer_is_open_to_the_internet" {
  module {
    source = "./modules/service"
  }

  # The rule that matters. Everything else in the VPC should be reachable only
  # through this one security group.
  assert {
    condition     = aws_vpc_security_group_ingress_rule.tasks_from_alb.cidr_ipv4 == null
    error_message = "The task security group accepts traffic from an address range rather than from the load balancer."
  }

  assert {
    condition = alltrue([
      aws_vpc_security_group_ingress_rule.alb_https.from_port == 443,
      aws_vpc_security_group_ingress_rule.alb_http.from_port == 80,
    ])
    error_message = "The load balancer should accept only 80 and 443 from the internet."
  }
}

run "tasks_run_in_private_subnets_with_no_public_address" {
  module {
    source = "./modules/service"
  }

  assert {
    condition     = aws_ecs_service.this.network_configuration[0].assign_public_ip == false
    error_message = "Tasks are given public addresses."
  }

  assert {
    condition = alltrue([
      for subnet in aws_ecs_service.this.network_configuration[0].subnets :
      contains(var.private_subnet_ids, subnet)
    ])
    error_message = "Tasks are running somewhere other than the private subnets."
  }
}

# The most common over-permission in an ECS setup: `secretsmanager:*` on the
# role, so a compromised container reads every secret in the account.
run "the_role_can_read_one_secret_and_no_others" {
  module {
    source = "./modules/service"
  }

  assert {
    condition     = !can(regex("\"Resource\":\\s*\"\\*\"", local.execution_extra_policy))
    error_message = "A policy statement grants access to every resource."
  }

  assert {
    condition     = can(regex(var.database_secret_arn, local.execution_extra_policy))
    error_message = "The policy does not name the database secret it is supposed to grant."
  }

  assert {
    condition     = !can(regex("secretsmanager:\\*", local.execution_extra_policy))
    error_message = "The policy grants every Secrets Manager action."
  }
}

run "http_redirects_rather_than_serving" {
  module {
    source = "./modules/service"
  }

  # An ALB that answers on HTTP is an ALB that accepts a session cookie in
  # clear text.
  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "redirect"
    error_message = "The HTTP listener serves traffic instead of redirecting to HTTPS."
  }

  assert {
    condition     = aws_lb_listener.http.default_action[0].redirect[0].status_code == "HTTP_301"
    error_message = "The redirect should be permanent."
  }
}

run "https_listener_appears_only_with_a_certificate" {
  module {
    source = "./modules/service"
  }

  assert {
    condition     = length(aws_lb_listener.https) == 0
    error_message = "An HTTPS listener was created without a certificate."
  }
}

run "https_uses_a_modern_policy_when_a_certificate_is_given" {
  module {
    source = "./modules/service"
  }

  variables {
    certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/abc"
  }

  assert {
    condition     = aws_lb_listener.https[0].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "The listener allows a TLS version below 1.2."
  }
}

run "a_failed_deploy_rolls_itself_back" {
  module {
    source = "./modules/service"
  }

  assert {
    condition = alltrue([
      aws_ecs_service.this.deployment_circuit_breaker[0].enable,
      aws_ecs_service.this.deployment_circuit_breaker[0].rollback,
    ])
    error_message = "A deploy that never becomes healthy would sit half-migrated instead of rolling back."
  }
}

run "the_database_url_is_a_secret_not_an_environment_variable" {
  module {
    source = "./modules/service"
  }

  # An environment variable is visible in the task definition, which anyone
  # with read access to ECS can see. A secret reference is resolved by the
  # agent at start.
  assert {
    condition = !can(regex(
      "\"name\":\\s*\"DATABASE_URL\"[^}]*\"value\":",
      aws_ecs_task_definition.this.container_definitions
    ))
    error_message = "DATABASE_URL is set as a plain environment variable."
  }

  assert {
    condition     = can(regex("valueFrom", aws_ecs_task_definition.this.container_definitions))
    error_message = "The task definition does not reference the secret."
  }
}

run "logs_have_a_retention_period" {
  module {
    source = "./modules/service"
  }

  # The default is "never expire", which is a bill that grows forever and is
  # nobody's job to notice.
  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days > 0
    error_message = "The log group keeps logs forever."
  }
}

run "scaling_out_is_faster_than_scaling_in" {
  module {
    source = "./modules/service"
  }

  # The reverse produces a service that removes capacity just as a spike
  # arrives.
  assert {
    condition = (
      aws_appautoscaling_policy.cpu.target_tracking_scaling_policy_configuration[0].scale_out_cooldown <
      aws_appautoscaling_policy.cpu.target_tracking_scaling_policy_configuration[0].scale_in_cooldown
    )
    error_message = "Scaling in is quicker than scaling out."
  }
}
