output "proxy_endpoint" {
  value = try(aws_db_proxy.postgres[0].endpoint, "")
}

output "proxy_arn" {
  value = try(aws_db_proxy.postgres[0].arn, "")
}
