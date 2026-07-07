variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "rendering_mode" {
  description = "Frontend rendering mode: static or container."
  type        = string

  validation {
    condition     = contains(["static", "container"], var.rendering_mode)
    error_message = "rendering_mode must be static or container."
  }
}

variable "alb_dns_name" {
  description = "ALB DNS name used as the CloudFront custom origin for container mode."
  type        = string
  default     = ""
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_200"
}
