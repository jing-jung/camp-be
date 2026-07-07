variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "cloudfront_arn" {
  description = "CloudFront distribution ARN to attach WAF"
  type        = string
}

variable "rate_limit" {
  description = "Rate limit per IP (requests per 5 minutes)"
  type        = number
  default     = 2000
}

variable "allowed_countries" {
  description = "List of allowed country codes (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = ["KR", "US", "JP"]
}

variable "enable_geo_blocking" {
  description = "Whether to enable geographic blocking"
  type        = bool
  default     = false
}
