output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.frontend.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.frontend.function_name
}

output "function_url" {
  description = "Lambda Function URL endpoint"
  value       = aws_lambda_function_url.frontend.function_url
}

output "function_url_id" {
  description = "Lambda Function URL ID"
  value       = aws_lambda_function_url.frontend.url_id
}
