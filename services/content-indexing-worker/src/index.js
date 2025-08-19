// Content Indexing Worker - GCS trigger -> chunk markdown -> Vertex AI embeddings -> Vector Search upsert
// Cloud Function entrypoint: indexWorldData

const {Storage} = require('@google-cloud/storage');
const aiplatform = require('@google-cloud/aiplatform');

// Embeddings client (PredictionService)
const {PredictionServiceClient} = aiplatform.v1;
const {helpers} = aiplatform;

// Vector Search Index client
const {v1beta1} = aiplatform;
const {IndexServiceClient} = v1beta1;

const storage = new Storage();

// Environment
const PROJECT_ID = process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT;
const LOCATION = process.env.LOCATION || 'us-central1';
const BUCKET_NAME = process.env.GCS_BUCKET_NAME; // optional safety check
const VECTOR_SEARCH_INDEX_ID = process.env.VECTOR_SEARCH_INDEX_ID;

// Model
const EMBEDDING_MODEL = process.env.EMBEDDING_MODEL || 'text-embedding-004';

// API endpoint derived from location
const API_ENDPOINT = `${LOCATION}-aiplatform.googleapis.com`;

// Chunking config
const CHUNK_SIZE = parseInt(process.env.CHUNK_SIZE || '1200', 10); // characters
const CHUNK_OVERLAP = parseInt(process.env.CHUNK_OVERLAP || '200', 10); // characters
const UPSERT_BATCH_SIZE = parseInt(process.env.UPSERT_BATCH_SIZE || '100', 10);

// Utility: robust path parse from GCS object name
function parsePath(name) {
  // Expected: users/{userId}/{bookId}/story_data/{dataType}/filename.md
  const parts = name.split('/');
  if (parts.length < 6) return null;
  if (parts[0] !== 'users') return null;
  const [_, userId, bookId, storyData, dataType] = parts;
  if (storyData !== 'story_data') return null;
  return {userId, bookId, dataType, 
    sourcePath: name,
  };
}

// Utility: ensure only markdown
function isMarkdown(name) {
  return /\.(md|markdown)$/i.test(name);
}

// Load file text from GCS
async function readGcsText(bucketName, name) {
  const file = storage.bucket(bucketName).file(name);
  const [exists] = await file.exists();
  if (!exists) throw new Error(`GCS object not found: gs://${bucketName}/${name}`);
  const [buf] = await file.download();
  return buf.toString('utf8');
}

// Simple markdown-aware chunking: split by headings/paragraphs, then merge to target size with overlaps
function chunkMarkdown(text, chunkSize = CHUNK_SIZE, overlap = CHUNK_OVERLAP) {
  // Normalize newlines
  const normalized = text.replace(/\r\n/g, '\n');
  // Split at ATX headings or blank lines
  const rawBlocks = normalized.split(/\n(?=(?:#{1,6}\s)|$)|\n\n+/g).map(s => s.trim()).filter(Boolean);

  // Merge blocks into chunks of approx size
  const chunks = [];
  let current = '';
  for (const block of rawBlocks) {
    if (!current) {
      current = block;
    } else if ((current.length + 1 + block.length) <= chunkSize) {
      current = current + '\n' + block;
    } else {
      chunks.push(current);
      current = block;
    }
  }
  if (current) chunks.push(current);

  // Add overlaps (character-based)
  if (overlap > 0 && chunks.length > 1) {
    const withOverlap = [];
    for (let i = 0; i < chunks.length; i++) {
      const prev = withOverlap[withOverlap.length - 1];
      const cur = chunks[i];
      if (!prev) {
        withOverlap.push(cur);
      } else {
        const tail = prev.slice(Math.max(0, prev.length - overlap));
        const merged = (tail + (tail && cur ? '\n' : '') + cur).slice(0, chunkSize * 2); // cap in case of large tail
        withOverlap.push(merged);
      }
    }
    return withOverlap;
  }
  return chunks;
}

// Generate embeddings for an array of texts
async function embedTexts(texts) {
  const client = new PredictionServiceClient({apiEndpoint: API_ENDPOINT});
  const endpoint = `projects/${PROJECT_ID}/locations/${LOCATION}/publishers/google/models/${EMBEDDING_MODEL}`;

  const embeddings = [];
  // The API processes one text per predict call for these models
  for (const content of texts) {
    const instance = helpers.toValue({content});
    const parameters = helpers.toValue({});
    const request = {endpoint, instances: [instance], parameters};
    const [response] = await client.predict(request);
    const predictions = response.predictions;
    if (!predictions || predictions.length === 0) throw new Error('Empty embedding response');
    const p = predictions[0];
    const embeddingsProto = p.structValue.fields.embeddings;
    const valuesProto = embeddingsProto.structValue.fields.values;
    const vector = valuesProto.listValue.values.map(v => v.numberValue);
    embeddings.push(vector);
  }
  return embeddings;
}

// Upsert datapoints into Vertex AI Vector Search
async function upsertVectors(vectors, meta) {
  const {userId, bookId, dataType, sourcePath} = meta;
  const indexName = `projects/${PROJECT_ID}/locations/${LOCATION}/indexes/${VECTOR_SEARCH_INDEX_ID}`;
  const client = new IndexServiceClient({apiEndpoint: API_ENDPOINT});

  // Build datapoints
  const datapoints = vectors.map((featureVector, i) => ({
    datapointId: `${sourcePath}#${i}`,
    featureVector,
    restricts: [
      {namespace: 'user_id', allowList: [userId]},
      {namespace: 'book_id', allowList: [bookId]},
      {namespace: 'data_type', allowList: [dataType]},
      {namespace: 'source_path', allowList: [sourcePath]},
    ],
  }));

  // Batch upserts
  for (let i = 0; i < datapoints.length; i += UPSERT_BATCH_SIZE) {
    const batch = datapoints.slice(i, i + UPSERT_BATCH_SIZE);
    await client.upsertDatapoints({index: indexName, datapoints: batch});
  }
}

// Main entrypoint for Cloud Function (GCS finalize trigger)
exports.indexContentData = async (event) => {
  if (!PROJECT_ID) throw new Error('GOOGLE_CLOUD_PROJECT is required');
  if (!VECTOR_SEARCH_INDEX_ID) throw new Error('VECTOR_SEARCH_INDEX_ID is required');

  // event may be legacy background or CloudEvent; normalize
  const data = event?.data ? event.data : event; // CloudEvent has {data: {...}}
  const bucket = data.bucket || BUCKET_NAME;
  const name = data.name;
  if (!bucket || !name) {
    console.log('Missing bucket or name in event, skipping.', {bucket, name});
    return;
  }

  // Safety filter: only process our bucket if provided
  if (BUCKET_NAME && bucket !== BUCKET_NAME) {
    console.log(`Event for bucket ${bucket} ignored; expecting ${BUCKET_NAME}`);
    return;
  }

  if (!isMarkdown(name)) {
    console.log(`Skipping non-markdown object: ${name}`);
    return;
  }

  const meta = parsePath(name);
  if (!meta) {
    console.log(`Skipping path that does not match story_data structure: ${name}`);
    return;
  }

  console.log(`Indexing gs://${bucket}/${name}`, meta);

  // Read file
  const text = await readGcsText(bucket, name);
  if (!text || !text.trim()) {
    console.log('Empty file; nothing to index.');
    return;
  }

  // Chunk
  const chunks = chunkMarkdown(text);
  console.log(`Created ${chunks.length} chunks (size≈${CHUNK_SIZE}, overlap=${CHUNK_OVERLAP})`);

  // Embed
  const vectors = await embedTexts(chunks);
  console.log(`Generated ${vectors.length} embeddings`);

  // Upsert
  await upsertVectors(vectors, meta);
  console.log(`Upserted ${vectors.length} vectors to index ${VECTOR_SEARCH_INDEX_ID}`);
};
