# `content-indexing-worker` Cloud Function

This Cloud Function is a critical component of the Retrieval-Augmented Generation (RAG) pipeline, responsible for **automatically processing and indexing your creative content** into Vertex AI Vector Search. It ensures that your LLM agents always have access to the latest and most relevant world lore, character details, and other story data.

## 📁 Directory Structure
```
├── content-indexing-worker/     # GCS triggered worker for RAG indexing
│   ├── src/
│   │   └── index.js
│   ├── package.json
│   └── .env.example     # Template for local environment variables
```

## 💡 Functionality

The `content-indexing-worker` operates as an event-driven service, triggered whenever a new Markdown file is uploaded or an existing one is updated in specific content folders within your Google Cloud Storage (GCS) bucket.

1.  **GCS Trigger**: It's configured to activate on `google.cloud.storage.object.v1.finalized` events in your main GCS content bucket, specifically targeting paths within `users/{userId}/{bookId}/story_data/`.
2.  **Content Ingestion**:
      * It reads the content of the newly uploaded or modified Markdown file (e.g., `magic_system.md`, `elara_protagonist.md`).
      * It **chunks** the text into smaller, semantically meaningful segments. This is crucial for effective RAG, as LLMs perform better with precise, relevant chunks.
3.  **Embedding Generation**:
      * Each text chunk is sent to the **Vertex AI Embedding Model (`text-embedding-004`)** to generate a **768-dimensional vector embedding**. These numerical representations capture the semantic meaning of the text.
4.  **Metadata Enrichment**:
      * During the embedding and ingestion process, the function extracts vital metadata from the GCS file path, including:
          * `user_id`: The ID of the user who owns the content.
          * `book_id`: The ID of the specific book project.
          * `data_type`: An identifier indicating the type of content (e.g., `'world_data'`, `'character_data'`, `'plot_data'`, `'locations_data'`). This is derived from the GCS sub-path (e.g., `story_data/world_data/`).
          * `source_path`: The full GCS path of the original Markdown file.
5.  **Vector Search Indexing**:
      * The generated embeddings, along with their associated metadata, are then ingested into your **Vertex AI Vector Search index**. This index uses the **`Tree-AH` algorithm** for efficient approximate nearest neighbor search, optimized for high recall and fast queries.
      * This makes the content immediately searchable by your AI agents for RAG purposes.

-----

## 🚀 Usage & Deployment

### **Trigger & Scope**

  * **Trigger Type**: Google Cloud Storage (`google.cloud.storage.object.v1.finalized`)
  * **Bucket**: `gs://your-project-id-fiction-data` (your main content bucket)
  * **Event Type**: `Finalize/Create` (meaning any new object upload or update to an existing object)
  * **Path Filter (Optional but Recommended)**: You can set a prefix filter during deployment (e.g., `users/`) to limit triggers to relevant content, or implement this logic within the function code itself to only process `.md` files in specific `story_data` subfolders.

### **Environment Variables**

This Cloud Function requires the following environment variables to be set during deployment:

  * `GOOGLE_CLOUD_PROJECT`: Your GCP project ID.
  * `GCS_BUCKET_NAME`: The name of your GCS bucket where the fiction data is stored.
  * `VECTOR_SEARCH_INDEX_ID`: The ID of your Vertex AI Vector Search Index.
  * `VECTOR_SEARCH_ENDPOINT_ID`: The ID of the deployed endpoint for your Vector Search Index.
  * `DEPLOYED_INDEX_ID`: The ID assigned when you deploy your index to the endpoint (often distinct from `VECTOR_SEARCH_INDEX_ID`).

### **Deployment Steps (Example using `gcloud`)**

```bash
# Ensure you are in the directory containing your Cloud Function's index.js and package.json
cd services/content-indexing-worker/

gcloud functions deploy content-indexing-worker \
  --runtime nodejs18 \
  --entry-point indexContentData \ # The name of the exported function in index.js
  --trigger-resource gs://your-project-id-fiction-data \
  --trigger-event google.cloud.storage.object.v1.finalized \
  --region us-central1 \ # Or your chosen region
  --set-env-vars GOOGLE_CLOUD_PROJECT=your-gcp-project-id,GCS_BUCKET_NAME=your-project-id-fiction-data,VECTOR_SEARCH_INDEX_ID=your-vector-search-index-id,VECTOR_SEARCH_ENDPOINT_ID=your-vector-search-endpoint-id,DEPLOYED_INDEX_ID=your-deployed-index-id \
  --memory 256MB \ # Adjust memory as needed for chunking/embedding calls
  --timeout 300s # Increase timeout for potentially larger files
```

### **Verification**

After deployment:

1.  **Upload a test Markdown file**: Place a `.md` file into a relevant GCS path (e.g., `gs://your-project-id-fiction-data/users/test_user/test_book/story_data/world_data/my_new_lore.md`).
2.  **Check Cloud Logging**: Navigate to `GCP Console > Operations > Logging > Logs Explorer`. Filter by `Function Name: content-indexing-worker`. Look for log entries indicating successful chunking, embedding, and indexing.
3.  **Verify in Vector Search**: In the Vertex AI Vector Search console, you can check your index metrics to see if the number of data points has increased. You can also perform a test query to confirm retrieval.

This function ensures that as your content grows, your RAG system stays updated automatically, providing relevant context to your AI agents.

-----