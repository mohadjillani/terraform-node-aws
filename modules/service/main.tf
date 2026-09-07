data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

# ---- Security groups -------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "The only thing in this VPC the internet can reach"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from anywhere"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from anywhere, redirected to HTTPS"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.tasks.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
  description                  = "To the tasks, on the container port only"
}

resource "aws_security_group" "tasks" {
  name        = "${var.name}-tasks"
  description = "Reachable only from the load balancer"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-tasks" })
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
  description                  = "From the load balancer only"
}

# Egress is open because the task pulls images, reads secrets and calls
# third-party APIs. The VPC endpoints in the network module keep most of that
# off the NAT gateway; locking egress down further needs a list of every
# outbound dependency, which is a real project rather than a line here.
resource "aws_vpc_security_group_egress_rule" "tasks_out" {
  security_group_id = aws_security_group.tasks.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound to anywhere"
}

# ---- Load balancer ---------------------------------------------------------

resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = var.tags
}

resource "aws_lb_target_group" "this" {
  name        = var.name
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }

  # Long enough for in-flight requests to finish, short enough that a deploy
  # does not take ten minutes. The default is 300 seconds.
  deregistration_delay = 30

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # Redirect rather than serve. An ALB that answers on HTTP is an ALB that
  # accepts a session cookie in clear text.
  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  count = var.certificate_arn == null ? 0 : 1

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# ---- IAM -------------------------------------------------------------------

# Policies are built with `jsonencode`, not with `aws_iam_policy_document`.
#
# The data source is the more idiomatic choice and it cannot be tested: under a
# mocked provider its `json` attribute is a fake string, so any assertion about
# what a policy grants would be an assertion about the mock. `jsonencode` is
# evaluated by Terraform itself, which makes the least-privilege rules in
# tests/service.tftest.hcl real checks against the real document.
locals {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  execution_extra_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadTheDatabaseSecret"
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        # One ARN. `secretsmanager:*` on `*` is the most common
        # over-permission in an ECS setup, and it means a compromised container
        # reads every secret in the account.
        Resource = var.database_secret_arn
      },
      {
        Sid      = "WriteToItsOwnLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.this.arn}:*"
      },
    ]
  })
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = local.assume_role_policy
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The execution role pulls the image and writes logs. It reads the secret
# because the agent injects it into the container before the task starts —
# scoped to one ARN and one log group, never to `*`.
resource "aws_iam_role_policy" "execution_extra" {
  name   = "${var.name}-execution-extra"
  role   = aws_iam_role.execution.id
  policy = local.execution_extra_policy
}

# The task role is what the application code itself gets. It starts with
# nothing: every permission here should be one someone had to argue for.
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = local.assume_role_policy
  tags               = var.tags
}

# ---- Task and service ------------------------------------------------------

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = var.container_image
      essential = true

      portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]

      secrets = [
        { name = "DATABASE_URL", valueFrom = var.database_secret_arn },
      ]

      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "PORT", value = tostring(var.container_port) },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # The container's own health check, separate from the load balancer's.
      # It is what lets ECS replace a task that is up but broken before the ALB
      # notices.
      healthCheck = {
        command     = ["CMD-SHELL", "node -e \"fetch('http://localhost:${var.container_port}${var.health_check_path}').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 20
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.name
    container_port   = var.container_port
  }

  # A deploy that never becomes healthy rolls itself back instead of leaving
  # the service half-migrated while someone works out what happened.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Long enough for a slow first boot — a Node process reading a secret and
  # opening a pool — without the ALB killing it.
  health_check_grace_period_seconds = 60

  depends_on = [aws_lb_listener.http]

  lifecycle {
    # The count is owned by autoscaling once the service exists; leaving it
    # here means every apply fights the scaler.
    ignore_changes = [desired_count]
  }
}

resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value = 60

    # Scale out quickly, scale in slowly. The reverse produces a service that
    # removes capacity just as a traffic spike arrives.
    scale_out_cooldown = 60
    scale_in_cooldown  = 300
  }
}
