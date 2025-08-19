# Enable required APIs
resource "google_project_service" "services" {
  for_each = toset([
    "aiplatform.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "eventarc.googleapis.com",
    "firestore.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "storage-api.googleapis.com",
    "storage.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# Service Accounts
resource "google_service_account" "api_sa" {
  account_id   = "api-service"
  display_name = "API Cloud Run service account"
}

resource "google_service_account" "agent_sa" {
  account_id   = "agent-jobs"
  display_name = "Agents (Cloud Run Jobs) service account"
}

resource "google_service_account" "functions_sa" {
  account_id   = "content-indexing-fn"
  display_name = "Content Indexing Cloud Function SA"
}

# GCS Bucket (versioned with lifecycle)
module "content_bucket" {
  source                             = "./modules/gcs"
  bucket_name                        = var.content_bucket_name
  location                           = var.location
  noncurrent_version_retention_days  = var.gcs_lifecycle_noncurrent_days
}

# Pub/Sub Topic
module "ai_tasks_topic" {
  source     = "./modules/pubsub"
  topic_name = var.pubsub_topic_name
}

# Firestore (Native Mode). Only one database per project. This is destructive if changed.
resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"
}

# Secret Manager placeholders (just creating secrets; versions can be added outside TF for security)
resource "google_secret_manager_secret" "vertex_api_key" {
  secret_id  = "vertex-api-key"
  replication {
    auto {}
  }
}

# Cloud Run Service - API (optional if image provided)
module "api_service" {
  source                = "./modules/cloud_run_service"
  create                = var.api_service_image != null
  project               = var.project_id
  name                  = "api-layer"
  location              = var.region
  image                 = var.api_service_image
  service_account_email = google_service_account.api_sa.email
  allow_unauthenticated = true
  env = {
    GOOGLE_CLOUD_PROJECT = var.project_id
    GCS_BUCKET_NAME      = var.content_bucket_name
    AI_TASKS_TOPIC       = module.ai_tasks_topic.topic_id
  }
  depends_on = [google_project_service.services]
}

# Cloud Run Job - world-building-agent (optional if image provided)
module "world_building_job" {
  source                = "./modules/cloud_run_service/job"
  create                = var.world_building_job_image != null
  name                  = "world-building-agent"
  location              = var.region
  image                 = var.world_building_job_image
  service_account_email = google_service_account.agent_sa.email
  env = {
    GOOGLE_CLOUD_PROJECT = var.project_id
    GCS_BUCKET_NAME      = var.content_bucket_name
    AI_TASKS_TOPIC       = module.ai_tasks_topic.topic_id
  }
  depends_on = [google_project_service.services]
}

# Cloud Function (2nd gen) - content-indexing-worker
module "content_indexing_worker" {
  source                = "./modules/cloud_function"
  name                  = "content-indexing-worker"
  location              = var.region
  runtime               = "nodejs18"
  entry_point           = "indexWorldData"
  service_account_email = google_service_account.functions_sa.email
  trigger_bucket        = module.content_bucket.name
  trigger_event_type    = "google.cloud.storage.object.v1.finalized"
  source_bucket         = var.function_source_bucket
  source_object         = var.function_source_object
  env = {
    GOOGLE_CLOUD_PROJECT     = var.project_id
    GCS_BUCKET_NAME          = module.content_bucket.name
  }
  depends_on = [google_project_service.services]
}

# Vertex AI Vector Search: Index, Endpoint, and Deployment
resource "google_vertex_ai_index" "rag_index" {
  display_name = var.index_display_name
  region       = var.region
  description  = "RAG index for fiction content"
  metadata { # Tree-AH config
    contents_delta_uri = null
    config {
      dimensions              = var.index_dimension
      approximate_neighbors_count = 100
      distance_measure_type   = var.index_distance_measure_type
      algorithm_config {
        tree_ah_config {
          leaf_node_embedding_count = 1000
          leaf_nodes_to_search_percent = 7
        }
      }
    }
  }
  depends_on = [google_project_service.services]
}

resource "google_vertex_ai_index_endpoint" "rag_endpoint" {
  display_name = "rag-index-endpoint"
  region       = var.region
  description  = "Endpoint for RAG index"
  depends_on   = [google_project_service.services]
}

resource "google_vertex_ai_index_endpoint_deployed_index" "rag_deployment" {
  index_endpoint = google_vertex_ai_index_endpoint.rag_endpoint.id
  deployed_index_id = "rag-index-deployment"
  index         = google_vertex_ai_index.rag_index.id
  automatic_resources {
    min_replica_count = 1
    max_replica_count = 1
  }
}

# IAM bindings (examples; tighten for least privilege as needed)
resource "google_project_iam_member" "api_sa_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_project_iam_member" "agent_sa_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.agent_sa.email}"
}

resource "google_project_iam_member" "functions_sa_storage" {
  project = var.project_id
  role    = "roles/storage.objectUser"
  member  = "serviceAccount:${google_service_account.functions_sa.email}"
}

resource "google_project_iam_member" "functions_sa_aiplatform" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.functions_sa.email}"
}
