variable "name_prefix" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_instance_class" {
  type = string
}

variable "allocated_storage_gb" {
  type = number
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "secret_arn" {
  type      = string
  sensitive = true
}

variable "log_group_name" {
  type = string
}
