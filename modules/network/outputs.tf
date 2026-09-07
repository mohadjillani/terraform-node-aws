output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "nat_gateway_count" {
  description = "Exposed so the cost script and the tests can assert on it."
  value       = length(aws_nat_gateway.this)
}
