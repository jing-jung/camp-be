# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"

  tags = {
    Name = "${var.name_prefix}-alerts"
  }
}

# Email Subscription
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Slack Subscription (via Lambda)
resource "aws_sns_topic_subscription" "slack" {
  count = var.slack_webhook_url != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier[0].arn
}

# Lambda for Slack Notifications
resource "aws_lambda_function" "slack_notifier" {
  count = var.slack_webhook_url != "" ? 1 : 0

  filename      = "${path.module}/slack_notifier.zip"
  function_name = "${var.name_prefix}-slack-notifier"
  role          = aws_iam_role.slack_notifier[0].arn
  handler       = "index.handler"
  runtime       = "python3.13"
  timeout       = 10

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }

  tags = {
    Name = "${var.name_prefix}-slack-notifier"
  }
}

resource "aws_iam_role" "slack_notifier" {
  count = var.slack_webhook_url != "" ? 1 : 0

  name = "${var.name_prefix}-slack-notifier-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "slack_notifier_logs" {
  count = var.slack_webhook_url != "" ? 1 : 0

  role       = aws_iam_role.slack_notifier[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_permission" "sns_invoke_slack" {
  count = var.slack_webhook_url != "" ? 1 : 0

  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

# === CloudWatch Alarms ===

# API Lambda Errors
resource "aws_cloudwatch_metric_alarm" "api_lambda_errors" {
  alarm_name          = "${var.name_prefix}-api-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "API Lambda errors exceed 10 per minute"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.api_lambda_function_name
  }
}

# API Lambda Duration (Performance)
resource "aws_cloudwatch_metric_alarm" "api_lambda_duration" {
  alarm_name          = "${var.name_prefix}-api-lambda-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Average"
  threshold           = "3000"  # 3 seconds
  alarm_description   = "API Lambda duration exceeds 3 seconds"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = var.api_lambda_function_name
  }
}

# API Lambda Throttles
resource "aws_cloudwatch_metric_alarm" "api_lambda_throttles" {
  alarm_name          = "${var.name_prefix}-api-lambda-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "API Lambda throttles detected"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.api_lambda_function_name
  }
}

# API Gateway 5xx Errors
resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx" {
  alarm_name          = "${var.name_prefix}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "API Gateway 5xx errors exceed 10 per minute"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = var.api_gateway_id
  }
}

# API Gateway 4xx Errors (potential attacks)
resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_high" {
  alarm_name          = "${var.name_prefix}-api-4xx-errors-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "100"  # High threshold, potential attack
  alarm_description   = "API Gateway 4xx errors exceed 100 per minute (potential attack)"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = var.api_gateway_id
  }
}

# RDS CPU Utilization
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.name_prefix}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "RDS CPU exceeds 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }
}

# RDS Database Connections
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "${var.name_prefix}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"  # Assuming max_connections ~100
  alarm_description   = "RDS connections exceed 80"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }
}

# RDS Free Storage Space
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${var.name_prefix}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "2000000000"  # 2GB
  alarm_description   = "RDS free storage space below 2GB"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }
}

# ElastiCache CPU (if Redis enabled)
resource "aws_cloudwatch_metric_alarm" "redis_cpu_high" {
  count = var.enable_elasticache ? 1 : 0

  alarm_name          = "${var.name_prefix}-redis-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "Redis CPU exceeds 75%"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ReplicationGroupId = var.redis_replication_group_id
  }
}

# === CloudWatch Dashboard ===
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-main-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: API Gateway Metrics
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", { stat = "Sum", label = "Total Requests", id = "m1" }],
            [".", "4XXError", { stat = "Sum", label = "4XX Errors", id = "m2" }],
            [".", "5XXError", { stat = "Sum", label = "5XX Errors", id = "m3" }],
            [{
              expression = "100*(m2+m3)/m1"
              label      = "Error Rate %"
              id         = "e1"
            }]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "API Gateway - Requests & Errors"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
        x      = 0
        y      = 0
        width  = 12
        height = 6
      },

      # Row 2: Lambda Performance
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", { stat = "Average", label = "Avg Duration (ms)" }],
            ["...", { stat = "Maximum", label = "Max Duration (ms)" }],
            [".", "ConcurrentExecutions", { stat = "Maximum", label = "Concurrent Executions" }],
            [".", "Throttles", { stat = "Sum", label = "Throttles" }]
          ]
          period = 300
          region = var.aws_region
          title  = "Lambda - Performance"
          yAxis = {
            left = {
              label = "Duration (ms)"
            }
            right = {
              label = "Count"
            }
          }
        }
        x      = 12
        y      = 0
        width  = 12
        height = 6
      },

      # Row 3: Lambda Errors
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Errors", { stat = "Sum", label = "Errors" }],
            [".", "Invocations", { stat = "Sum", label = "Invocations" }],
            [{
              expression = "100*m1/m2"
              label      = "Error Rate %"
              id         = "e1"
            }]
          ]
          period = 300
          region = var.aws_region
          title  = "Lambda - Errors & Invocations"
        }
        x      = 0
        y      = 6
        width  = 12
        height = 6
      },

      # Row 4: RDS Performance
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", { stat = "Average", label = "CPU %" }],
            [".", "DatabaseConnections", { stat = "Average", label = "Connections" }],
            [".", "ReadLatency", { stat = "Average", label = "Read Latency (ms)", yAxis = "right" }],
            [".", "WriteLatency", { stat = "Average", label = "Write Latency (ms)", yAxis = "right" }]
          ]
          period = 300
          region = var.aws_region
          title  = "RDS - Performance"
          yAxis = {
            left = {
              label = "CPU % / Connections"
              min   = 0
            }
            right = {
              label = "Latency (ms)"
              min   = 0
            }
          }
        }
        x      = 12
        y      = 6
        width  = 12
        height = 6
      },

      # Row 5: RDS Storage & IOPS
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", { stat = "Average", label = "Free Storage (bytes)" }],
            [".", "ReadIOPS", { stat = "Average", label = "Read IOPS", yAxis = "right" }],
            [".", "WriteIOPS", { stat = "Average", label = "Write IOPS", yAxis = "right" }]
          ]
          period = 300
          region = var.aws_region
          title  = "RDS - Storage & IOPS"
        }
        x      = 0
        y      = 12
        width  = 12
        height = 6
      },

      # Row 6: ElastiCache (if enabled)
      {
        type = "metric"
        properties = {
          metrics = var.enable_elasticache ? [
            ["AWS/ElastiCache", "CPUUtilization", { stat = "Average", label = "CPU %" }],
            [".", "DatabaseMemoryUsagePercentage", { stat = "Average", label = "Memory %" }],
            [".", "CacheHits", { stat = "Sum", label = "Cache Hits", yAxis = "right" }],
            [".", "CacheMisses", { stat = "Sum", label = "Cache Misses", yAxis = "right" }]
          ] : []
          period = 300
          region = var.aws_region
          title  = "ElastiCache - Performance"
        }
        x      = 12
        y      = 12
        width  = 12
        height = 6
      },

      # Row 7: Cost Estimation
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", {
              stat  = "Maximum"
              label = "Estimated Charges (USD)"
            }]
          ]
          period = 86400
          region = "us-east-1"  # Billing metrics only in us-east-1
          title  = "Estimated Monthly Cost"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
        x      = 0
        y      = 18
        width  = 24
        height = 6
      }
    ]
  })
}

# Log Insights Queries (saved for quick access)
resource "aws_cloudwatch_query_definition" "api_errors" {
  name = "${var.name_prefix}-api-errors"

  log_group_names = [
    "/aws/lambda/${var.api_lambda_function_name}"
  ]

  query_string = <<-EOT
    fields @timestamp, @message
    | filter @message like /ERROR/
    | sort @timestamp desc
    | limit 100
  EOT
}

resource "aws_cloudwatch_query_definition" "slow_requests" {
  name = "${var.name_prefix}-slow-requests"

  log_group_names = [
    "/aws/lambda/${var.api_lambda_function_name}"
  ]

  query_string = <<-EOT
    fields @timestamp, @duration, @message
    | filter @type = "REPORT"
    | filter @duration > 1000
    | sort @duration desc
    | limit 100
  EOT
}
