variable "create" { type = bool default = true }
variable "project" { type = string default = null }
variable "name" { type = string }
variable "location" { type = string }
variable "image" { type = string }
variable "service_account_email" { type = string }
variable "env" { type = map(string) default = {} }
