# CloudWatch Logs for Lambda
resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.name_prefix}-frontend-lambda-logs"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "frontend_lambda" {
  name = "${var.name_prefix}-frontend-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-frontend-lambda-role"
  }
}

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.frontend_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function with Container Image
resource "aws_lambda_function" "frontend" {
  function_name = local.function_name
  role          = aws_iam_role.frontend_lambda.arn
  package_type  = "Image"
  image_uri     = "${var.container_image}:${var.image_tag}"
  
  memory_size = var.memory_mb
  timeout     = var.timeout_seconds
  
  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = merge(
      var.environment_variables,
      {
        # Lambda Web Adapter configuration
        AWS_LAMBDA_EXEC_WRAPPER = "/opt/bootstrap"
        PORT                    = "3000"
        HOSTNAME                = "0.0.0.0"
        NODE_ENV                = "production"
      }
    )
  }

  depends_on = [
    aws_cloudwatch_log_group.frontend,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]

  tags = {
    Name = "${var.name_prefix}-frontend-lambda"
  }
}

# Lambda Function URL (Public)
resource "aws_lambda_function_url" "frontend" {
  function_name      = aws_lambda_function.frontend.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = true
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    max_age           = 86400
  }
}

# Permission for Function URL invocation
resource "aws_lambda_permission" "function_url" {
  statement_id           = "AllowFunctionURLInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.frontend.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

locals {
  function_name = "${var.name_prefix}-frontend-lambda"
}
