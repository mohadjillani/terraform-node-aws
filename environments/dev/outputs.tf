output "alb_dns_name" {
  value = module.service.alb_dns_name
}

output "assets_domain_name" {
  value = module.cdn.distribution_domain_name
}

output "database_endpoint" {
  value     = module.data.endpoint
  sensitive = true
}
