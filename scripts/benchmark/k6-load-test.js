// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                        // straylight-llm //
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
//     "The sky above the port was the color of television,
//      tuned to a dead channel."
//
//                                                               — Neuromancer
//
// k6 load testing script for straylight-llm gateway.
//
// Usage:
//   k6 run scripts/benchmark/k6-load-test.js
//   k6 run --vus 50 --duration 60s scripts/benchmark/k6-load-test.js
//   k6 run -e BASE_URL=https://your-prod-url scripts/benchmark/k6-load-test.js
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// ════════════════════════════════════════════════════════════════════════════════
//                                                                    // config
// ════════════════════════════════════════════════════════════════════════════════

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const MODEL = __ENV.MODEL || 'google/gemini-2.0-flash-001';
const API_KEY = __ENV.OPENROUTER_API_KEY || '';

// Custom metrics
const chatLatency = new Trend('chat_latency', true);
const cacheHits = new Counter('cache_hits');
const cacheMisses = new Counter('cache_misses');
const errorRate = new Rate('errors');

// ════════════════════════════════════════════════════════════════════════════════
//                                                                  // scenarios
// ════════════════════════════════════════════════════════════════════════════════

export const options = {
  scenarios: {
    // Smoke test - verify the system works
    smoke: {
      executor: 'constant-vus',
      vus: 1,
      duration: '10s',
      startTime: '0s',
      tags: { scenario: 'smoke' },
    },

    // Load test - normal production load
    load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 10 },  // Ramp up
        { duration: '1m', target: 10 },   // Stay at 10
        { duration: '30s', target: 50 },  // Ramp to 50
        { duration: '2m', target: 50 },   // Stay at 50
        { duration: '30s', target: 0 },   // Ramp down
      ],
      startTime: '15s',
      tags: { scenario: 'load' },
    },

    // Stress test - find breaking point
    stress: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 100 },  // Ramp to 100
        { duration: '2m', target: 100 },  // Stay at 100
        { duration: '1m', target: 200 },  // Ramp to 200
        { duration: '2m', target: 200 },  // Stay at 200
        { duration: '1m', target: 0 },    // Ramp down
      ],
      startTime: '5m',
      tags: { scenario: 'stress' },
    },

    // Spike test - sudden traffic burst
    spike: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '10s', target: 10 },   // Normal load
        { duration: '5s', target: 500 },   // Spike!
        { duration: '30s', target: 500 },  // Stay at spike
        { duration: '10s', target: 10 },   // Back to normal
        { duration: '30s', target: 10 },   // Stay normal
        { duration: '10s', target: 0 },    // Ramp down
      ],
      startTime: '12m',
      tags: { scenario: 'spike' },
    },
  },

  thresholds: {
    // 95th percentile latency should be < 5s
    'chat_latency': ['p(95)<5000'],
    // Error rate should be < 5%
    'errors': ['rate<0.05'],
    // Health checks should always succeed
    'http_req_duration{name:health}': ['p(99)<100'],
  },
};

// ════════════════════════════════════════════════════════════════════════════════
//                                                                   // helpers
// ════════════════════════════════════════════════════════════════════════════════

function getHeaders() {
  const headers = {
    'Content-Type': 'application/json',
  };
  if (API_KEY) {
    headers['Authorization'] = `Bearer ${API_KEY}`;
  }
  return headers;
}

// Generate varied prompts to test cache behavior
const prompts = [
  'What is 2+2?',
  'Hello, how are you?',
  'Explain quantum computing briefly.',
  'What is the capital of France?',
  'Write a haiku about programming.',
  'What is machine learning?',
  'How does TCP/IP work?',
  'Explain REST APIs.',
  'What is functional programming?',
  'Define artificial intelligence.',
];

function getRandomPrompt() {
  return prompts[Math.floor(Math.random() * prompts.length)];
}

// Deterministic prompt for cache testing
function getCacheablePrompt() {
  return 'What is 2+2?'; // Always the same, temperature=0 will cache
}

// ════════════════════════════════════════════════════════════════════════════════
//                                                                     // tests
// ════════════════════════════════════════════════════════════════════════════════

export default function () {
  const scenario = __ENV.SCENARIO || 'mixed';

  switch (scenario) {
    case 'cache':
      testCacheHits();
      break;
    case 'varied':
      testVariedPrompts();
      break;
    case 'health':
      testHealthOnly();
      break;
    default:
      testMixed();
  }
}

// Mixed workload - realistic traffic pattern
function testMixed() {
  // 70% varied prompts, 20% cacheable, 10% health checks
  const rand = Math.random();
  
  if (rand < 0.1) {
    testHealthOnly();
  } else if (rand < 0.3) {
    testCacheHits();
  } else {
    testVariedPrompts();
  }
  
  sleep(Math.random() * 2); // Random think time 0-2s
}

// Test health endpoint (should be fast)
function testHealthOnly() {
  const res = http.get(`${BASE_URL}/health`, {
    tags: { name: 'health' },
  });

  check(res, {
    'health: status 200': (r) => r.status === 200,
    'health: response ok': (r) => r.json('status') === 'ok',
  });
}

// Test cache hits with deterministic requests
function testCacheHits() {
  const payload = JSON.stringify({
    model: MODEL,
    messages: [{ role: 'user', content: getCacheablePrompt() }],
    max_tokens: 10,
    temperature: 0, // Deterministic = cacheable
  });

  const start = Date.now();
  const res = http.post(`${BASE_URL}/v1/chat/completions`, payload, {
    headers: getHeaders(),
    tags: { name: 'chat_cacheable' },
  });
  const duration = Date.now() - start;

  chatLatency.add(duration);

  const success = check(res, {
    'chat: status 200': (r) => r.status === 200,
    'chat: has choices': (r) => r.json('choices') !== undefined,
  });

  if (!success) {
    errorRate.add(1);
  } else {
    errorRate.add(0);
    // Cache hit if < 100ms
    if (duration < 100) {
      cacheHits.add(1);
    } else {
      cacheMisses.add(1);
    }
  }

  sleep(0.5);
}

// Test with varied prompts (cache misses)
function testVariedPrompts() {
  const payload = JSON.stringify({
    model: MODEL,
    messages: [{ role: 'user', content: getRandomPrompt() }],
    max_tokens: 50,
  });

  const start = Date.now();
  const res = http.post(`${BASE_URL}/v1/chat/completions`, payload, {
    headers: getHeaders(),
    tags: { name: 'chat_varied' },
  });
  const duration = Date.now() - start;

  chatLatency.add(duration);

  const success = check(res, {
    'chat: status 200': (r) => r.status === 200,
    'chat: has choices': (r) => r.json('choices') !== undefined,
  });

  if (!success) {
    errorRate.add(1);
    console.log(`Error: ${res.status} - ${res.body}`);
  } else {
    errorRate.add(0);
  }

  sleep(1);
}

// ════════════════════════════════════════════════════════════════════════════════
//                                                                   // summary
// ════════════════════════════════════════════════════════════════════════════════

export function handleSummary(data) {
  const summary = {
    timestamp: new Date().toISOString(),
    metrics: {
      chat_latency_p50: data.metrics.chat_latency?.values?.['p(50)'],
      chat_latency_p95: data.metrics.chat_latency?.values?.['p(95)'],
      chat_latency_p99: data.metrics.chat_latency?.values?.['p(99)'],
      cache_hits: data.metrics.cache_hits?.values?.count,
      cache_misses: data.metrics.cache_misses?.values?.count,
      error_rate: data.metrics.errors?.values?.rate,
      total_requests: data.metrics.http_reqs?.values?.count,
      rps: data.metrics.http_reqs?.values?.rate,
    },
  };

  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'benchmark-results.json': JSON.stringify(summary, null, 2),
  };
}

function textSummary(data, opts) {
  const m = data.metrics;
  return `
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                              // straylight-llm benchmark //
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Chat Latency:
    p50: ${m.chat_latency?.values?.['p(50)']?.toFixed(0) || 'N/A'}ms
    p95: ${m.chat_latency?.values?.['p(95)']?.toFixed(0) || 'N/A'}ms
    p99: ${m.chat_latency?.values?.['p(99)']?.toFixed(0) || 'N/A'}ms

  Cache Performance:
    Hits:   ${m.cache_hits?.values?.count || 0}
    Misses: ${m.cache_misses?.values?.count || 0}
    Rate:   ${((m.cache_hits?.values?.count || 0) / ((m.cache_hits?.values?.count || 0) + (m.cache_misses?.values?.count || 1)) * 100).toFixed(1)}%

  Throughput:
    Total Requests: ${m.http_reqs?.values?.count || 0}
    RPS:            ${m.http_reqs?.values?.rate?.toFixed(1) || 0}

  Errors:
    Rate: ${((m.errors?.values?.rate || 0) * 100).toFixed(2)}%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
`;
}
