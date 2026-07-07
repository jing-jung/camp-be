variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "vpc_id" {
  description = "VPC id for the frontend load balancer and ECS tasks."
  type        = string
}

variable "alb_subnet_ids" {
  description = "Public subnet ids for the internet-facing ALB."
  type        = list(string)
}

variable "ecs_subnet_ids" {
  description = "Subnet ids for ECS Fargate tasks."
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign a public IP to ECS tasks. Required when tasks run in public subnets without NAT."
  type        = bool
  default     = true
}

variable "container_port" {
  description = "Container port exposed by the Next.js server."
  type        = number
  default     = 3000
}

variable "desired_count" {
  description = "Desired ECS task count. Keep 0 until the first container image is pushed."
  type        = number
  default     = 1
}

variable "cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "container_image" {
  description = "Optional full container image URI. Defaults to the managed ECR repository latest tag."
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "ECR image tag used when container_image is empty."
  type        = string
  default     = "latest"
}

variable "environment_variables" {
  description = "Plain environment variables injected into the frontend container."
  type        = map(string)
  default     = {}
}

variable "health_check_path" {
  description = "ALB target group health check path."
  type        = string
  default     = "/"
}

# Auto Scaling variables
variable "enable_autoscaling" {
  description = "Enable ECS Service Auto Scaling."
  type        = bool
  default     = true
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks."
  type        = number
  default     = 4
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for auto scaling."
  type        = number
  default     = 70
}

variable "memory_target_value" {
  description = "Target memory utilization percentage for auto scaling."
  type        = number
  default     = 80
}

variable "scale_in_cooldown" {
  description = "Cooldown period in seconds after a scale-in activity."
  type        = number
  default     = 300  # 5 minutes
}

variable "scale_out_cooldown" {
  description = "Cooldown period in seconds after a scale-out activity."
  type        = number
  default     = 60   # 1 minute
}
