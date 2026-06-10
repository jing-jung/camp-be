output "db_endpoint" {
  value = try(aws_db_instance.postgres[0].endpoint, null)
}

output "db_instance_identifier" {
  value = try(aws_db_instance.postgres[0].identifier, "")
}

output "db_secret_arn" {
  value     = try(aws_db_instance.postgres[0].master_user_secret[0].secret_arn, var.secret_arn)
  sensitive = true
}
