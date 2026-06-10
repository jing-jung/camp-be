variable "name_prefix" {
  type = string
}

variable "callback_urls" {
  type = list(string)
}

variable "logout_urls" {
  type = list(string)
}

variable "hosted_ui_domain_prefix" {
  type    = string
  default = ""
}
