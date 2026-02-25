// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                            // straylight-llm // load-tests // streaming //
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// k6 load test for streaming /v1/chat/completions endpoint.
//
// Usage:
//   k6 run streaming.js
//   k6 run --vus 20 --duration 1m streaming.js
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('stream_errors');
const chunksReceived = new Counter('chunks_received');
const streamLatency = new Trend('stream_latency_ms');
const firstChunkLatency = new Trend('ttfb_stream_ms');

// Test configuration
export const options = {
    scenarios: {
        // Sustained streaming load
        sustained_streaming: {
            executor: 'constant-vus',
            vus: 10,
            duration: '2m',
            tags: { scenario: 'sustained' },
        },
        // Burst of concurrent streams
        burst_streaming: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: [
                { duration: '10s', target: 50 },   // Burst
                { duration: '30s', target: 50 },  // Hold
                { duration: '10s', target: 0 },   // Cool down
            ],
            startTime: '2m30s',
            tags: { scenario: 'burst' },
        },
    },
    thresholds: {
        'ttfb_stream_ms': ['p(95)<200'],   // First chunk < 200ms
        'stream_errors': ['rate<0.05'],     // < 5% error rate
        'http_req_failed': ['rate<0.01'],   // < 1% HTTP failures
    },
};

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const API_KEY = __ENV.API_KEY || 'test-key';

// Streaming request payload
const streamingRequest = {
    model: 'gpt-4',
    messages: [
        { role: 'system', content: 'You are a helpful assistant.' },
        { role: 'user', content: 'Write a short story about a robot learning to paint.' }
    ],
    stream: true,
    max_tokens: 200,
    temperature: 0.8,
};

// Parse SSE chunk
function parseSSEChunk(chunk) {
    if (!chunk || chunk.trim() === '') return null;
    if (chunk.startsWith('data: ')) {
        const data = chunk.slice(6);
        if (data === '[DONE]') return { done: true };
        try {
            return JSON.parse(data);
        } catch {
            return null;
        }
    }
    return null;
}

// Main test function
export default function() {
    const params = {
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${API_KEY}`,
            'Accept': 'text/event-stream',
        },
        responseType: 'text',
    };

    const startTime = Date.now();
    let firstChunkTime = null;
    let chunkCount = 0;
    
    const response = http.post(
        `${BASE_URL}/v1/chat/completions`,
        JSON.stringify(streamingRequest),
        params
    );

    const endTime = Date.now();
    
    // Process response
    if (response.status === 200) {
        const body = response.body;
        const lines = body.split('\n');
        
        for (const line of lines) {
            const chunk = parseSSEChunk(line);
            if (chunk) {
                if (firstChunkTime === null) {
                    firstChunkTime = Date.now();
                    firstChunkLatency.add(firstChunkTime - startTime);
                }
                if (!chunk.done) {
                    chunkCount++;
                    chunksReceived.add(1);
                }
            }
        }
    }

    const totalLatency = endTime - startTime;
    streamLatency.add(totalLatency);

    // Validate response
    const success = check(response, {
        'status is 200': (r) => r.status === 200,
        'content-type is text/event-stream': (r) => 
            r.headers['Content-Type']?.includes('text/event-stream') || 
            r.headers['content-type']?.includes('text/event-stream'),
        'received chunks': () => chunkCount > 0,
        'has X-Request-Id header': (r) => 
            r.headers['X-Request-Id'] !== undefined ||
            r.headers['x-request-id'] !== undefined,
    });

    errorRate.add(!success);

    // Longer sleep for streaming - these are expensive
    sleep(Math.random() * 2 + 1);
}

// Setup
export function setup() {
    const healthResponse = http.get(`${BASE_URL}/health`);
    if (healthResponse.status !== 200) {
        throw new Error(`Server not healthy: ${healthResponse.status}`);
    }
    console.log('Server health check passed for streaming tests');
    return { startTime: Date.now() };
}

// Teardown
export function teardown(data) {
    const duration = (Date.now() - data.startTime) / 1000;
    console.log(`Streaming test completed in ${duration.toFixed(2)} seconds`);
}
