resource "aws_cloudwatch_log_group" "api_lambda" {
  name              = "/aws/lambda/${var.name_prefix}-api"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.name_prefix}-http-api"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "rds" {
  name              = "/aws/rds/${var.name_prefix}-postgres"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "amplify" {
  name              = "/aws/amplify/${var.name_prefix}-web"
  retention_in_days = 14
}
