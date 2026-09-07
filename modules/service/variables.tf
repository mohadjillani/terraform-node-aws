variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "For the load balancer only. Tasks never run here."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Where the tasks run."
  type        = list(string)
}

variable "container_image" {
  description = "The image to run, from ECR."
  type        = string
}

variable "container_port" {
  type    = number
  default = 3000
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "cpu" {
  description = "Fargate CPU units. 256 is a quarter of a vCPU."
  type        = number
  default     = 512
}

variable "memory" {
  type    = number
  default = 1024
}

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  type    = number
  default = 10
}

variable "database_secret_arn" {
  description = <<-EOT
    The one secret this task may read.

    A specific ARN, never a wildcard: `secretsmanager:*` on a task role means a
    compromised container reads every secret in the account, and it is the
    single most common over-permission in an ECS setup.
  EOT
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "certificate_arn" {
  description = "ACM certificate for HTTPS. Without one the listener is HTTP only, which the module refuses in prod."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
