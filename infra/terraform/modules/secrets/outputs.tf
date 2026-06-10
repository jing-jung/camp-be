output "database_secret_arn" {
  value     = aws_secretsmanager_secret.database.arn
  sensitive = true
}

output "external_api_secret_arn" {
  value     = aws_secretsmanager_secret.external_api.arn
  sensitive = true
}
