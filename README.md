# 📚 Intelligent Author System
This repository contains the complete codebase for an AI-powered fiction writing assistant. It's designed to help authors create detailed fictional worlds and narratives, leveraging Large Language Models (LLMs) and advanced data management techniques to ensure consistency, factuality, and a seamless writing experience.

## 🎯 Project Overview
This system is built on Google Cloud Platform (GCP) and follows a modular, asynchronous architecture. It comprises:

* **Frontend UI:** A web-based interface for users to manage their books, edit content, and trigger AI generation tasks.
* **API Layer:** A Cloud Run service that acts as the entry point for UI requests, handles user authentication, and dispatches tasks.
* **Asynchronous AI Agents:** Cloud Run Jobs that perform the heavy lifting of AI generation (e.g., world-building, character creation, chapter drafting) in the background.
* **Data Management:** Google Cloud Storage (GCS) for all content, backed by Vertex AI Vector Search for Retrieval-Augmented Generation (RAG) and Firestore for real-time job status and rich version history metadata.

## 📁 Folder Structure
This project uses a mono-repo setup, organizing all code into a single repository while maintaining clear separation and independent dependency management for each service.

* `./.github/`
    * `workflows/`: GitHub Actions or Cloud Build configurations for CI/CD pipelines.
* `./docs/`: Project documentation, architectural diagrams, decision logs.
* `./infra/`: **Infrastructure as Code (IaC)**.
    * `./terraform/`: **Terraform** configurations for provisioning all GCP resources (GCS buckets, Pub/Sub topics, Cloud Run services, Cloud Functions, Vertex AI indexes, Firestore, IAM roles).
    * `./cloudbuild/`: Cloud Build YAML files (cloudbuild.yaml) defining the build and deployment steps for each service.
    * `./service-configs/`: Environment variable files (.env format) specific to each deployed service. Sensitive variables are loaded from GCP Secret Manager.
* `./scripts/`: Utility scripts for local development setup, mass deployments, and environment variable generation.
* `./shared/`: **Shared code, types, and utilities** used across multiple services. Managed as a separate workspace to reduce redundancy.
    * `./constants/`: Global constants (e.g., GCS path prefixes, Firestore collection names).
    * `./models/`: Common data models (e.g., Pub/Sub message payloads, Firestore document schemas).
    * `./utils/`: Generic utility functions (e.g., GCS path builders, common error handling).
* `./services/`: Contains independent backend services. Each subdirectory is a separate Node.js application, managed as an npm/Yarn/pnpm workspace.
    * `./api-layer/`: The HTTP entry point. Handles user authentication (Firebase), validates requests, and publishes messages to Pub/Sub.
    * `./world-building-agent/`: A Cloud Run Job triggered by Pub/Sub. Generates world lore, leverages RAG, and saves to GCS.
    * `./indexing-worker/`: A Cloud Function triggered by GCS object finalization. Processes new/updated Markdown files, generates embeddings, and ingests them into Vertex AI Vector Search.
    * `./character-agent/`: Another Cloud Run Job for generating character details.
    * `...`: Other planned agents (e.g., chapter-generation-agent/, editing-agent/).
* `./ui/`: The frontend web application (e.g., React, Vue). Users interact with this via Firebase Hosting.

## 💡 Core Architectural Concepts
### Google Cloud Platform (GCP) Services

* **Firebase Authentication:** Manages user signup, login, and session management for the UI. Provides secure user_ids.
* **Google Cloud Storage (GCS):** The primary data store for all creative content (Markdown files).
* **Cloud Firestore:** Used for real-time tracking of AI job statuses, user metadata, and rich version history metadata for GCS objects.
* **Cloud Pub/Sub:** Enables asynchronous communication between the API layer and the AI agents, decoupling processes and improving responsiveness.
* **Cloud Run (Services & Jobs):**
    * **Cloud Run Service:** For the API layer (HTTP-triggered, always-on for requests).
    * **Cloud Run Jobs:** For the asynchronous AI agents (Pub/Sub-triggered, scale-to-zero, ideal for long-running or burstable tasks).
* **Cloud Functions:** For specific event-driven tasks like automatic content indexing (triggered by GCS events).
* **Vertex AI (Generative AI & Vector Search):v
    * **Generative AI:** Powers the LLMs (e.g., Gemini 1.5 Pro) for content generation.
    * **Vector Search:** Used for Retrieval-Augmented Generation (RAG). Stores vectorized embeddings of your world and character data.

### Asynchronous Processing with Pub/Sub & Cloud Run Jobs
User requests (e.g., "Generate Chapter") are immediately acknowledged by the API layer, which publishes a message to a Pub/Sub topic. A dedicated Cloud Run Job (your AI agent) subscribes to this topic and processes the request in the background. This ensures the UI remains responsive and complex generation tasks don't time out HTTP requests. Firestore is updated in real-time to show job progress.

### Retrieval-Augmented Generation (RAG)
RAG is critical for grounding the AI's responses in your specific fictional universe, preventing "hallucinations."

1. **Indexing (Cloud Function `indexing-worker`):** When you save or update Markdown files in GCS (e.g., story_data/world_data/*.md), a GCS trigger invokes the indexing-worker Cloud Function. This function:
    * Reads the Markdown file.
    * Chunks the content into smaller, semantically meaningful pieces.
    * Uses **Vertex AI Embedding Models** (e.g., `text-embedding-004`) to convert each text chunk into a high-dimensional vector (embedding).
    * Ingests these embeddings into a single Vertex AI Vector Search Index. Crucially, it attaches metadata to each embedding, including:
        * `user_id`
        * `book_id`
        * `data_type` (e.g., `'world_data'`, `'character_data'`, `'plot_data'`, `'locations_data'`)
        * `source_path` (original GCS path)
    * **Index Configuration:** The index uses the Tree-AH algorithm (for balanced speed and recall), 768 dimensions (matching text-embedding-004), and likely defaults to COSINE_DISTANCE for similarity.
2. **Retrieval (AI Agents):** When an AI agent needs to generate content, it first crafts a query based on the task and context. This query is sent to the Vertex AI Vector Search Index with filters on `user_id`, `book_id`, and the `data_type` it specifically needs (e.g., only `world_data`).
2. **Augmentation:** The relevant text chunks retrieved from Vector Search are then injected directly into the prompt sent to the Vertex AI LLM (e.g., Gemini 1.5 Pro), giving the LLM the specific lore to generate grounded responses.

### Content Versioning & History
Every single Markdown file (e.g., chapters, character sheets, world lore) stored in GCS has its history meticulously preserved.

1. **GCS Object Versioning:** Enabled on your main GCS bucket. Whenever a file is overwritten or deleted, GCS automatically saves a non-current version with a unique `generation` ID.
2. **Firestore Metadata** (`document_versions` collection): Complementing GCS, Firestore stores rich, searchable metadata about why each version was created. Each entry includes:
    * `userId`, `bookId`, `filePath` (the document's GCS path)
    * `gcsGenerationId`: The specific GCS version ID (essential for retrieval).
    * `timestamp`: When the version was created.
    * `actionType`: USER_SAVE, AI_GENERATE, AI_REVISE, USER_ROLLBACK, INITIAL_CREATION.
    * `agentName` (if AI-generated) or `editorUserId` (if human-edited).
    * `description`: A human-readable summary of the change.
    * `prevGcsGenerationId` (for linking history).

3. Process:
    * Any backend agent or API endpoint that saves a Markdown file to GCS will, after the save operation, capture the `gcsGenerationId` of the newly saved object.
    * It then creates a new document in the `document_versions` Firestore collection with all relevant metadata.
4. UI Interaction: The frontend can:
    * Query Firestore to display a chronological list of versions for any document.
    * Use the `gcsGenerationId` to fetch and display the content of any historical version directly from GCS.
    * Trigger a "rollback" operation, which downloads a historical version and saves it as a new current version in GCS, logging this as a USER_ROLLBACK in Firestore.
5. **Cost Management:** **GCS Lifecycle Management** rules are configured on the bucket to automatically delete older non-current versions after a defined period (e.g., 90 days or after 5 newer versions) to control storage costs.

### Multi-Tenancy
The system is designed to securely handle multiple users and their distinct projects:
* **GCS Structure:** `users/[user_id]/[book_id]/...` ensures strict data isolation.
* **Firestore Data:** All Firestore documents are scoped by userId and bookId.
* **API Security:** Firebase Authentication verifies user identity, and backend logic ensures users can only access their own data.

### Mono-repo with Workspaces
This project uses npm/Yarn/pnpm workspaces to manage multiple `package.json` files within a single repository.
* Root `package.json`: Defines the `workspaces` (e.g., `services/*`, `ui`). It typically has `private: true` to prevent accidental publishing.
* Child `package.json`s: Each service (`services/api-layer/`, `ui/`, `shared/utils/`) has its own `package.json`, listing only its specific dependencies and scripts (start, test, build).
* **Benefits:** Isolates dependencies, enables independent scripting, streamlines deployment of individual services, and allows for shared code packages (e.g., `@your-monorepo-scope/utils`) that can be imported by other services.

## 💻 Local Development Setup
Follow these steps to get your development environment running.

1. **Clone the Repository:**
    ```
    git clone https://github.com/your-org/your-fiction-project-monorepo.git
    cd your-fiction-project-monorepo
    ```
2. **Install Node.js & npm/Yarn/pnpm:** Ensure you have Node.js (LTS recommended) and your preferred package manager installed.
3. **Install Root Dependencies:**
    ```
    npm install # or yarn install or pnpm install
    ```
This will install dependencies for all workspaces.

4. **Google Cloud CLI & Authentication:**
    * Install the gcloud CLI: https://cloud.google.com/sdk/docs/install
    * Authenticate:
    ```
    gcloud auth login
    gcloud config set project your-gcp-project-id # Replace with your project ID
    gcloud auth application-default login # Important for local SDKs
    ```
5. Firebase CLI & Emulators:
    * Install Firebase CLI: `npm install -g firebase-tools`
    * Initialize Emulators (if not already done, run from repo root): `firebase init emulators`
        * Select **Authentication, Firestore, Pub/Sub** (and Hosting if you want to serve the UI locally via emulator).
    * Start Emulators: `firebase emulators:start`

6. **Create Local `.env` Files:**

* For each service (`services/api-layer/`, `services/world-building-agent/`, etc.) and the `ui/` folder, copy its `.env.example` file to `.env`.
* Edit each `.env` file to configure local paths and emulator addresses.
    * `FICTION_BASE_ROOT`: Set this in your system environment or a `.env` file at the mono-repo root (if you create one) and then ensure it's picked up by the individual service's `.env` (e.g., by sourcing it). For services, you might specify a local temp directory like `/tmp/my_fiction_projects`.
    * `GOOGLE_CLOUD_PROJECT`: Your GCP Project ID.
    * `GCS_BUCKET_NAME`: A dedicated development GCS bucket in your actual GCP project. For local testing, your services will connect to this.
    * `VECTOR_SEARCH_INDEX_ID`, `VECTOR_SEARCH_ENDPOINT_ID`: Your actual Vertex AI Vector Search IDs (even for local testing, as the service is cloud-based).
    * `AI_TASKS_TOPIC`: Your Pub/Sub topic name (e.g., `ai-generation-tasks`).
7. **Run Services:**
    * In separate terminal windows, navigate to each service directory and start it:
    ```
    cd services/api-layer/
    npm start # or node src/index.js
    ```
    ```
    cd services/world-building-agent/
    npm start # or node src/index.js (or equivalent for Cloud Run Job simulation)
    ```
    ```
    cd ui/
    npm start
    ```

8. **Manual Cloud Function Testing:** For GCS-triggered Cloud Functions (indexing-worker), you'll likely need to manually trigger them locally (using gcloud functions deploy --trigger-topic or a local HTTP trigger if you modify it for that) or deploy them to a development GCP project for testing.

## 🚀 Deployment (CI/CD)
The project leverages GitHub Actions (or Cloud Build) for continuous integration and deployment to GCP.

1. **Infrastructure as Code (IaC):** All GCP resources are defined in `infra/terraform/`.
    * First-time setup: Apply Terraform manually from your local machine:
    ```
    cd infra/terraform/
    terraform init
    terraform apply
    ```
    This creates your GCS bucket, Pub/Sub, Firestore, Cloud Run services, Cloud Functions, and Vertex AI resources.

2. **Cloud Build Configurations:** Each service has a `cloudbuild.yaml` in `infra/cloudbuild/`. These files specify how Docker images are built and pushed to Container Registry, and how Cloud Run services/jobs or Cloud Functions are deployed.

3. **Environment Variable Management:** Production environment variables are configured via `infra/service-configs/*.env` files. Sensitive variables are handled by GCP Secret Manager and referenced during deployment.

4. **GitHub Actions Workflow (`.github/workflows/main.yaml`):**

    * This workflow is triggered on pushes to the main branch.
    * It authenticates with GCP using a Service Account Key stored in GitHub Secrets.
    * It invokes Cloud Build for each service that needs to be deployed.
    * It deploys the UI to Firebase Hosting.

5. **Monitoring:** All logs from deployed services will appear in GCP Cloud Logging. Set up alerts and dashboards in Cloud Monitoring as needed.

## 👋 Contributing
Contributions are welcome! Please follow these guidelines:

* Fork the repository and create a new branch for your feature or bug fix.
* Ensure your code adheres to the project's coding standards.
* Write clear commit messages.
* Test your changes thoroughly.
* Open a Pull Request with a detailed description of your changes.