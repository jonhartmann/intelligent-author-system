resource "google_cloud_run_v2_job" "this" {
  count    = var.create ? 1 : 0
  name     = var.name
  location = var.location

  template {
    template {
      service_account = var.service_account_email
      containers {
        image = var.image
        dynamic "env" {
          for_each = var.env
          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }
  }
}

output "job_name" {
  value = var.create ? google_cloud_run_v2_job.this[0].name : null
}
