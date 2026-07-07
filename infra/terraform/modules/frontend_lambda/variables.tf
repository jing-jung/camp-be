variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "container_image" {
  description = "Docker image URI for Next.js standalone app"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
}

variable "memory_mb" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 2048
}

variable "timeout_seconds" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "reserved_concurrent_executions" {
  description = "Amount of reserved concurrent executions (-1 for unreserved)"
  type        = number
  default     = -1
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 7
}
