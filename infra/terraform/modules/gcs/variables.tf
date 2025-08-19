variable "bucket_name" { type = string }
variable "location"    { type = string }
variable "noncurrent_version_retention_days" { type = number default = 90 }
