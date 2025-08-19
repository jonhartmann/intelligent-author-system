output "content_bucket_name" {
  description = "GCS bucket for content"
  value       = module.content_bucket.name
}

output "pubsub_topic_id" {
  description = "AI tasks Pub/Sub topic ID"
  value       = module.ai_tasks_topic.topic_id
}

output "vertex_index_id" {
  description = "Vertex AI Index ID"
  value       = google_vertex_ai_index.rag_index.id
}

output "vertex_index_endpoint_id" {
  description = "Vertex AI Index Endpoint ID"
  value       = google_vertex_ai_index_endpoint.rag_endpoint.id
}
