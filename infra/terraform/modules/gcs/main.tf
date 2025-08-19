resource "google_storage_bucket" "this" {
  name                        = var.bucket_name
  location                    = var.location
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning { enabled = true }

  lifecycle_rule {
    condition { num_newer_versions = 5 }
    action    { type = "Delete" }
  }

  lifecycle_rule {
    condition { is_live = false, age = var.noncurrent_version_retention_days }
    action    { type = "Delete" }
  }
}

output "name" {
  value = google_storage_bucket.this.name
}
