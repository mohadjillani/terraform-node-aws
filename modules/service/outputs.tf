output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "task_security_group_id" {
  value = aws_security_group.tasks.id
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.this.name
}
