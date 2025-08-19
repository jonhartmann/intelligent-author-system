resource "google_cloud_run_v2_service" "this" {
  count    = var.create ? 1 : 0
  name     = var.name
  location = var.location

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

resource "google_cloud_run_v2_service_iam_member" "noauth" {
  count    = var.create && var.allow_unauthenticated ? 1 : 0
  location = var.location
  project  = var.project
  name     = google_cloud_run_v2_service.this[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "service_name" {
  value = var.create ? google_cloud_run_v2_service.this[0].name : null
}
