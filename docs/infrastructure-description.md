# ☁️ GCP Resources Deployed via Terraform
This document outlines the Google Cloud Platform (GCP) resources managed and deployed by Terraform for the AI Fiction Writing System. Terraform ensures that our infrastructure is consistently provisioned, versioned, and auditable.

## 🏗️ Core GCP Resources
The following resources form the backbone of the application's infrastructure:

1. Google Cloud Storage (GCS) Bucket
    * Purpose: The primary storage for all creative content (Markdown files for world data, characters, plot, outlines, drafts, feedback) and generated AI output. It serves as the knowledge base for RAG and the persistent store for all user data.
    * Key Features: Enabled with Object Versioning to maintain a full history of all content edits and creations, crucial for the book-writing process. Lifecycle Management rules are applied to manage version retention and optimize costs.
    * Terraform Module: `infra/terraform/modules/gcs/`

2. Cloud Firestore (Native Mode) 
    * Purpose: A NoSQL document database used for:
        * Job Status Tracking: Real-time updates on AI generation tasks (queued, processing, completed, failed).* Book & User Metadata: Storing references to user projects and their properties.
        * Version History Metadata: A rich log (e.g., `document_versions collection`) detailing why each content version was created (AI-generated, user edit, rollback) and linking to its specific GCS `generation` ID.
    * Terraform Module: Managed as part of the main Terraform configuration.

3. Cloud Pub/Sub Topic
    * Purpose: Provides an asynchronous messaging queue. The API layer publishes messages to this topic to trigger AI agents (Cloud Run Jobs) in the background. This decouples the frontend interaction from long-running AI tasks, ensuring UI responsiveness.
    * Terraform Module: `infra/terraform/modules/pubsub/`

4. Vertex AI Resources (Generative AI & Vector Search)
    * Purpose: The core AI components for generation and retrieval.
    * Generative AI: Access to Large Language Models (LLMs) like Gemini 1.5 Pro for creative content generation. Terraform ensures the Vertex AI API is enabled and proper permissions are set.
    * Vector Search Index & Endpoint: This is where your text embeddings for RAG are stored.
        * The index is configured with the `Tree-AH` algorithm, designed for efficient approximate nearest neighbor searches for high-dimensional vectors (e.g., 768 dimensions from `text-embedding-004`).
        * The deployed endpoint makes the index queryable by your AI agents.
    * Terraform Module: Managed as part of the main Terraform configuration (enabling APIs, potentially configuring index structure).

5. Cloud Run Services
    * Purpose: Hosts your stateless, containerized backend services.
    * API Layer: An HTTP-triggered service that handles all incoming requests from the frontend, performs authentication, and dispatches tasks via Pub/Sub.
    * AI Agents (Cloud Run Jobs): Pub/Sub-triggered jobs (e.g., `world-building-agent`, `character-agent`, `chapter-generation-agent`) that scale from zero, process Pub/Sub messages, perform AI generation, and update Firestore.
    * Terraform Module: `infra/terraform/modules/cloud_run_service/` (reusable for each agent).

6. Cloud Functions
    * Purpose: Event-driven serverless functions for specific tasks.
        * `content-indexing-worker`: A GCS-triggered Cloud Function that automatically processes new/updated Markdown files, generates embeddings, and ingests them into Vertex AI Vector Search for RAG.
        * `...`: Additional workers and will be added as needed 
    * Terraform Module: `infra/terraform/modules/cloud_function/` (reusable for each function).

7. Identity and Access Management (IAM) Roles & Service Accounts
    * Purpose: Defines permissions for all GCP services and components to interact securely with each other. Terraform provisions:
        * Service Accounts: Dedicated service accounts for Cloud Run services, Cloud Functions, and Vertex AI processes.
        * IAM Bindings: Specific roles are granted (e.g., Cloud Run Invoker, Pub/Sub Publisher/Subscriber, Cloud Storage Object Admin, Firestore Editor, Vertex AI User) to ensure least-privilege access.

8. Secret Manager
    Purpose: Securely stores sensitive configuration data (e.g., API keys, external service credentials) that should not be hardcoded or exposed in environment variables directly in source control. Terraform defines the secrets, and then your services can be granted IAM permission to access them at runtime.

## 🚀 Deployment with Terraform
Terraform is used to define the desired state of your GCP infrastructure. By running `terraform apply` from the `infra/terraform/` directory, all these resources are provisioned and configured according to the defined .tf files. This ensures that your development, staging, and production environments can be consistently replicated and managed.
