// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                            // straylight-llm // load-tests // embeddings //
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// k6 load test for /v1/embeddings endpoint.
//
// Embedding endpoints are typically:
//   - Higher throughput (faster than completions)
//   - Lower latency requirements
//   - Often called in batches
//
// Usage:
//   k6 run embeddings.js
//   k6 run --vus 100 --duration 1m embeddings.js
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('embedding_errors');
const latencyTrend = new Trend('embedding_latency_ms');
const embeddingDimsTrend = new Trend('embedding_dimensions');

// Test configuration
export const options = {
    scenarios: {
        // High throughput test - embeddings should be fast
        throughput: {
            executor: 'constant-arrival-rate',
            rate: 100,              // 100 RPS
            timeUnit: '1s',
            duration: '1m',
            preAllocatedVUs: 50,
            maxVUs: 200,
            tags: { scenario: 'throughput' },
        },
        // Batch processing test
        batch_processing: {
            executor: 'constant-vus',
            vus: 20,
            duration: '2m',
            startTime: '1m30s',
            tags: { scenario: 'batch' },
        },
    },
    thresholds: {
        'embedding_latency_ms': ['p(95)<100', 'p(99)<200'],  // Embeddings should be fast
        'http_req_failed': ['rate<0.01'],
        'embedding_errors': ['rate<0.05'],
    },
};

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const API_KEY = __ENV.API_KEY || 'test-key';

// Sample texts for embedding
const sampleTexts = [
    'The quick brown fox jumps over the lazy dog.',
    'Machine learning is a subset of artificial intelligence.',
    'Natural language processing enables computers to understand human language.',
    'Vector embeddings represent text as high-dimensional numerical vectors.',
    'Semantic search uses embeddings to find conceptually similar documents.',
    'Transformer models have revolutionized natural language processing.',
    'Attention mechanisms allow models to focus on relevant parts of the input.',
    'Pre-trained language models can be fine-tuned for specific tasks.',
    'Large language models are trained on massive amounts of text data.',
    'Embeddings capture semantic meaning in continuous vector spaces.',
];

// Generate batch of texts
function generateBatch(size) {
    const batch = [];
    for (let i = 0; i < size; i++) {
        batch.push(sampleTexts[Math.floor(Math.random() * sampleTexts.length)]);
    }
    return batch;
}

// Request payloads
function singleTextRequest() {
    return {
        model: 'text-embedding-ada-002',
        input: sampleTexts[Math.floor(Math.random() * sampleTexts.length)],
    };
}

function batchRequest(batchSize) {
    return {
        model: 'text-embedding-ada-002',
        input: generateBatch(batchSize),
    };
}

// Main test function
export default function() {
    // 60% single text, 30% small batch (5), 10% large batch (20)
    const rand = Math.random();
    let payload;
    let requestType;
    
    if (rand < 0.6) {
        payload = singleTextRequest();
        requestType = 'single';
    } else if (rand < 0.9) {
        payload = batchRequest(5);
        requestType = 'batch_5';
    } else {
        payload = batchRequest(20);
        requestType = 'batch_20';
    }

    const params = {
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${API_KEY}`,
        },
        tags: { request_type: requestType },
    };

    const startTime = Date.now();
    const response = http.post(
        `${BASE_URL}/v1/embeddings`,
        JSON.stringify(payload),
        params
    );
    const latency = Date.now() - startTime;

    // Record metrics
    latencyTrend.add(latency);

    // Validate response
    const success = check(response, {
        'status is 200': (r) => r.status === 200,
        'response has data array': (r) => {
            try {
                const body = JSON.parse(r.body);
                return Array.isArray(body.data);
            } catch {
                return false;
            }
        },
        'embeddings have correct dimensions': (r) => {
            try {
                const body = JSON.parse(r.body);
                if (!body.data || body.data.length === 0) return false;
                const dims = body.data[0].embedding?.length;
                if (dims) {
                    embeddingDimsTrend.add(dims);
                    return dims > 0;
                }
                return false;
            } catch {
                return false;
            }
        },
        'response has usage': (r) => {
            try {
                const body = JSON.parse(r.body);
                return body.usage !== undefined;
            } catch {
                return false;
            }
        },
        'latency < 100ms (p95 target)': () => latency < 100,
    });

    errorRate.add(!success);

    // Minimal sleep - embeddings should be hammered
    sleep(Math.random() * 0.1);
}

// Setup
export function setup() {
    const healthResponse = http.get(`${BASE_URL}/health`);
    if (healthResponse.status !== 200) {
        throw new Error(`Server not healthy: ${healthResponse.status}`);
    }
    console.log('Server health check passed for embedding tests');
    return { startTime: Date.now() };
}

// Teardown
export function teardown(data) {
    const duration = (Date.now() - data.startTime) / 1000;
    console.log(`Embedding test completed in ${duration.toFixed(2)} seconds`);
}
