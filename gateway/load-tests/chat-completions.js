// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                // straylight-llm // load-tests // chat //
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// k6 load test for /v1/chat/completions endpoint.
//
// Usage:
//   k6 run chat-completions.js
//   k6 run --vus 50 --duration 30s chat-completions.js
//   k6 run --env BASE_URL=http://localhost:8080 chat-completions.js
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const latencyTrend = new Trend('latency_ms');
const ttfbTrend = new Trend('ttfb_ms');

// Test configuration
export const options = {
    scenarios: {
        // Smoke test: verify basic functionality
        smoke: {
            executor: 'constant-vus',
            vus: 1,
            duration: '10s',
            startTime: '0s',
            tags: { scenario: 'smoke' },
        },
        // Load test: typical production load
        load: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: [
                { duration: '30s', target: 10 },  // Ramp up
                { duration: '1m', target: 10 },   // Hold
                { duration: '30s', target: 50 },  // Increase
                { duration: '1m', target: 50 },   // Hold
                { duration: '30s', target: 0 },   // Ramp down
            ],
            startTime: '15s',
            tags: { scenario: 'load' },
        },
        // Stress test: find breaking point
        stress: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: [
                { duration: '1m', target: 100 },  // Ramp up
                { duration: '2m', target: 100 },  // Hold
                { duration: '1m', target: 200 },  // Push harder
                { duration: '2m', target: 200 },  // Hold at peak
                { duration: '1m', target: 0 },    // Ramp down
            ],
            startTime: '4m',
            tags: { scenario: 'stress' },
        },
    },
    thresholds: {
        'http_req_duration': ['p(95)<500', 'p(99)<1000'],  // 95th < 500ms, 99th < 1s
        'http_req_failed': ['rate<0.01'],                  // Error rate < 1%
        'errors': ['rate<0.05'],                           // Custom error rate < 5%
    },
};

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const API_KEY = __ENV.API_KEY || 'test-key';

// Request payloads
const minimalRequest = {
    model: 'gpt-4',
    messages: [
        { role: 'user', content: 'Hello, how are you?' }
    ],
};

const fullRequest = {
    model: 'gpt-4-turbo',
    messages: [
        { role: 'system', content: 'You are a helpful assistant.' },
        { role: 'user', content: 'What is the capital of France?' },
        { role: 'assistant', content: 'The capital of France is Paris.' },
        { role: 'user', content: 'What is its population?' },
    ],
    temperature: 0.7,
    max_tokens: 100,
    top_p: 0.9,
    presence_penalty: 0.5,
    frequency_penalty: 0.5,
};

const largeRequest = {
    model: 'gpt-4',
    messages: Array.from({ length: 50 }, (_, i) => ({
        role: i % 2 === 0 ? 'user' : 'assistant',
        content: `Message ${i + 1}: ${generateContent(100)}`,
    })),
    max_tokens: 500,
};

// Generate random content of approximately n words
function generateContent(wordCount) {
    const words = ['lorem', 'ipsum', 'dolor', 'sit', 'amet', 'consectetur',
                   'adipiscing', 'elit', 'sed', 'do', 'eiusmod', 'tempor',
                   'incididunt', 'ut', 'labore', 'et', 'dolore', 'magna'];
    return Array.from({ length: wordCount }, () => 
        words[Math.floor(Math.random() * words.length)]
    ).join(' ');
}

// Main test function
export default function() {
    // Select request type based on random distribution
    // 70% minimal, 20% full, 10% large
    const rand = Math.random();
    let payload;
    let requestType;
    
    if (rand < 0.7) {
        payload = minimalRequest;
        requestType = 'minimal';
    } else if (rand < 0.9) {
        payload = fullRequest;
        requestType = 'full';
    } else {
        payload = largeRequest;
        requestType = 'large';
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
        `${BASE_URL}/v1/chat/completions`,
        JSON.stringify(payload),
        params
    );
    const latency = Date.now() - startTime;

    // Record metrics
    latencyTrend.add(latency);
    ttfbTrend.add(response.timings.waiting);

    // Validate response
    const success = check(response, {
        'status is 200': (r) => r.status === 200,
        'response has id': (r) => {
            try {
                const body = JSON.parse(r.body);
                return body.id !== undefined;
            } catch {
                return false;
            }
        },
        'response has choices': (r) => {
            try {
                const body = JSON.parse(r.body);
                return Array.isArray(body.choices) && body.choices.length > 0;
            } catch {
                return false;
            }
        },
        'latency < 500ms': () => latency < 500,
    });

    errorRate.add(!success);

    // Small random sleep to avoid thundering herd
    sleep(Math.random() * 0.5);
}

// Setup function (runs once before test)
export function setup() {
    // Verify server is reachable
    const healthResponse = http.get(`${BASE_URL}/health`);
    if (healthResponse.status !== 200) {
        throw new Error(`Server not healthy: ${healthResponse.status}`);
    }
    console.log('Server health check passed');
    return { startTime: Date.now() };
}

// Teardown function (runs once after test)
export function teardown(data) {
    const duration = (Date.now() - data.startTime) / 1000;
    console.log(`Test completed in ${duration.toFixed(2)} seconds`);
}
