output "security_group_id" {
  value = aws_security_group.db.id
}

output "secret_arn" {
  description = "The one secret the task role is allowed to read."
  value       = aws_secretsmanager_secret.database_url.arn
}

output "endpoint" {
  value = aws_db_instance.this.address
}

output "instance_identifier" {
  value = aws_db_instance.this.identifier
}
