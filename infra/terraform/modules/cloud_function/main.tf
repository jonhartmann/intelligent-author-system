resource "google_cloudfunctions2_function" "this" {
  name     = var.name
  location = var.location

  build_config {
    runtime     = var.runtime
    entry_point = var.entry_point
    source {
      storage_source {
        bucket = var.source_bucket
        object = var.source_object
      }
    }
    environment_variables = var.env
  }

  service_config {
    available_memory      = "256M"
    timeout_seconds       = 300
    max_instance_count    = 3
    service_account_email = var.service_account_email
    ingress_settings      = "ALLOW_INTERNAL_ONLY"
    environment_variables = var.env
  }

  event_trigger {
    trigger_region = var.location
    event_type     = var.trigger_event_type
    retry_policy   = "RETRY_POLICY_RETRY"
    event_filters {
      attribute = "bucket"
      value     = var.trigger_bucket
    }
  }
}

output "function_name" {
  value = google_cloudfunctions2_function.this.name
}
