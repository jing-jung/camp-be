variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "alert_email" {
  description = "Email address for alarm notifications"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "api_lambda_function_name" {
  description = "API Lambda function name"
  type        = string
}

variable "frontend_lambda_function_name" {
  description = "Frontend Lambda function name"
  type        = string
  default     = ""
}

variable "api_gateway_id" {
  description = "API Gateway ID"
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS instance identifier"
  type        = string
}

variable "redis_replication_group_id" {
  description = "ElastiCache replication group ID"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "enable_elasticache" {
  description = "Whether ElastiCache is enabled"
  type        = bool
  default     = false
}
