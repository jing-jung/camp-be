variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "function_url" {
  description = "Lambda Function URL (without https://)"
  type        = string
}

variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}

variable "default_ttl" {
  description = "Default TTL for cached objects"
  type        = number
  default     = 0
}

variable "max_ttl" {
  description = "Maximum TTL for cached objects"
  type        = number
  default     = 0
}
