variable "topic_name" { type = string }

resource "google_pubsub_topic" "this" {
  name = var.topic_name
}

output "topic_id" {
  value = google_pubsub_topic.this.id
}
