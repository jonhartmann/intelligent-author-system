variable "name" { type = string }
variable "location" { type = string }
variable "runtime" { type = string }
variable "entry_point" { type = string }
variable "service_account_email" { type = string }
variable "trigger_bucket" { type = string }
variable "trigger_event_type" { type = string }
variable "source_bucket" { type = string }
variable "source_object" { type = string }
variable "env" { type = map(string) default = {} }
