variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "Default region for resources"
  type        = string
  default     = "us-central1"
}

variable "location" {
  description = "Multi-region or region for specific resources (e.g., us-central1)"
  type        = string
  default     = "us-central1"
}

variable "content_bucket_name" {
  description = "GCS bucket name for fiction content"
  type        = string
}

variable "gcs_lifecycle_noncurrent_days" {
  description = "Days to retain noncurrent versions before deletion"
  type        = number
  default     = 90
}

variable "pubsub_topic_name" {
  description = "Pub/Sub topic for AI tasks"
  type        = string
  default     = "ai-generation-tasks"
}

variable "api_service_image" {
  description = "Container image for API Cloud Run service"
  type        = string
  default     = null
}

variable "world_building_job_image" {
  description = "Container image for world-building-agent Cloud Run job"
  type        = string
  default     = null
}

variable "index_display_name" {
  description = "Vertex AI Index display name"
  type        = string
  default     = "fiction-rag-index"
}

variable "index_dimension" {
  description = "Embedding vector dimension (e.g., 768 for text-embedding-004)"
  type        = number
  default     = 768
}

variable "index_distance_measure_type" {
  description = "Distance type for vector search (SQUARED_L2_DISTANCE, COSINE_DISTANCE, DOT_PRODUCT_DISTANCE)"
  type        = string
  default     = "COSINE_DISTANCE"
}

variable "index_algorithm_config" {
  description = "Algorithm config for Vector Search (Tree-AH)"
  type        = string
  default     = "tree-ah"
}

variable "function_source_bucket" {
  description = "Bucket containing the function source archive (for Cloud Functions 2nd gen deploy)"
  type        = string
  default     = null
}

variable "function_source_object" {
  description = "Object name (zip) for the function source code"
  type        = string
  default     = null
}
