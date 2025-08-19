variable "create" { type = bool default = true }
variable "project" { type = string }
variable "name" { type = string }
variable "location" { type = string }
variable "image" { type = string }
variable "service_account_email" { type = string }
variable "allow_unauthenticated" { type = bool default = false }
variable "env" { type = map(string) default = {} }
