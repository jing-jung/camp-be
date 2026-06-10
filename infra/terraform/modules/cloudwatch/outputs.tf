output "api_lambda_log_group_name" {
  value = aws_cloudwatch_log_group.api_lambda.name
}

output "api_gateway_log_group_name" {
  value = aws_cloudwatch_log_group.api_gateway.name
}

output "api_gateway_log_group_arn" {
  value = aws_cloudwatch_log_group.api_gateway.arn
}

output "rds_log_group_name" {
  value = aws_cloudwatch_log_group.rds.name
}

output "amplify_log_group_name" {
  value = aws_cloudwatch_log_group.amplify.name
}
