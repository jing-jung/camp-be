variable "name_prefix" {
  type = string
}

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "enable_rds" {
  type    = bool
  default = false
}

variable "enable_amplify" {
  type    = bool
  default = false
}
