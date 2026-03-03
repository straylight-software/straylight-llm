# API Reference

straylight-llm provides an OpenAI-compatible API plus additional endpoints for proofs and observability.

## Base URL

```
http://localhost:8080
```

## Authentication

Currently, straylight-llm does not require authentication for incoming requests. Provider authentication is handled via environment variables.

For production deployments, place straylight-llm behind a reverse proxy (nginx, Caddy) with authentication.

---

## Endpoints

### Health Check

```
GET /health
```

Returns gateway health and provider status.

**Response:**
```json
{
  "status": "healthy",
  "uptime": 3600,
  "providers": [
    {"name": "venice", "status": "available", "latencyMs": 45},
    {"name": "openrouter", "status": "available", "latencyMs": 120}
  ],
  "circuitBreakers": {
    "venice": "closed",
    "openrouter": "closed"
  },
  "version": "0.1.0"
}
```

---

### List Models

```
GET /v1/models
```

Returns available models from all configured providers.

**Response:**
```json
{
  "object": "list",
  "data": [
    {
      "id": "gpt-4",
      "object": "model",
      "created": 1687882410,
      "owned_by": "straylight"
    },
    {
      "id": "claude-3-opus",
      "object": "model",
      "created": 1687882410,
      "owned_by": "straylight"
    }
  ]
}
```

---

### Chat Completions

```
POST /v1/chat/completions
```

Create a chat completion (OpenAI-compatible).

**Request:**
```json
{
  "model": "gpt-4",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello!"}
  ],
  "temperature": 0.7,
  "max_tokens": 1000
}
```

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `model` | string | Yes | Model ID |
| `messages` | array | Yes | Array of message objects |
| `temperature` | number | No | Sampling temperature (0-2) |
| `max_tokens` | integer | No | Maximum tokens to generate |
| `top_p` | number | No | Nucleus sampling parameter |
| `stop` | string/array | No | Stop sequences |
| `presence_penalty` | number | No | Presence penalty (-2 to 2) |
| `frequency_penalty` | number | No | Frequency penalty (-2 to 2) |

**Message Object:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `role` | string | Yes | `system`, `user`, or `assistant` |
| `content` | string | Yes | Message content |

**Response:**
```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1687882410,
  "model": "gpt-4",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! How can I help you today?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 8,
    "total_tokens": 18
  },
  "x_straylight": {
    "requestId": "550e8400-e29b-41d4-a716-446655440000",
    "provider": "venice",
    "latencyMs": 450
  }
}
```

**Response Headers:**
- `X-Request-Id`: Unique request ID for proof retrieval
- `X-Provider`: Provider that handled the request

---

### Streaming Chat Completions

```
POST /v1/chat/completions/stream
```

Stream chat completions via Server-Sent Events.

**Request:** Same as `/v1/chat/completions`

**Response:** `text/event-stream`

```
data: {"id":"chatcmpl-abc123","choices":[{"delta":{"content":"Hello"}}]}

data: {"id":"chatcmpl-abc123","choices":[{"delta":{"content":"!"}}]}

data: {"id":"chatcmpl-abc123","choices":[{"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

---

### Text Completions

```
POST /v1/completions
```

Create a text completion (legacy OpenAI format).

**Request:**
```json
{
  "model": "gpt-3.5-turbo-instruct",
  "prompt": "Once upon a time",
  "max_tokens": 100,
  "temperature": 0.7
}
```

**Response:**
```json
{
  "id": "cmpl-abc123",
  "object": "text_completion",
  "created": 1687882410,
  "model": "gpt-3.5-turbo-instruct",
  "choices": [
    {
      "text": ", in a land far away...",
      "index": 0,
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 4,
    "completion_tokens": 100,
    "total_tokens": 104
  }
}
```

---

### Embeddings

```
POST /v1/embeddings
```

Create embeddings for text.

**Request:**
```json
{
  "model": "text-embedding-ada-002",
  "input": "The quick brown fox"
}
```

**Response:**
```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "index": 0,
      "embedding": [0.0023, -0.0091, ...]
    }
  ],
  "model": "text-embedding-ada-002",
  "usage": {
    "prompt_tokens": 4,
    "total_tokens": 4
  }
}
```

---

### Discharge Proofs

```
GET /v1/proof/:requestId
```

Retrieve the cryptographic discharge proof for a completed request.

**Response:**
```json
{
  "requestId": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-02-27T12:00:00Z",
  "coeffects": [
    "NetworkAccess:venice.ai:443",
    "AuthUsage:bearer"
  ],
  "providersUsed": ["venice"],
  "contentHash": "sha256:a3f2b1c4d5e6f7890123456789abcdef",
  "signature": "ed25519:MEUCIQDx..."
}
```

**Proof Fields:**

| Field | Description |
|-------|-------------|
| `requestId` | UUID of the original request |
| `timestamp` | ISO 8601 timestamp |
| `coeffects` | List of tracked coeffects (network access, auth usage) |
| `providersUsed` | List of providers that were tried |
| `contentHash` | SHA256 hash of request+response |
| `signature` | Ed25519 signature over the proof |

---

### Real-time Events

```
GET /v1/events
```

Subscribe to real-time events via Server-Sent Events.

**Response:** `text/event-stream`

```
event: request.started
data: {"requestId":"abc123","model":"gpt-4","timestamp":"..."}

event: request.completed
data: {"requestId":"abc123","provider":"venice","latencyMs":450}

event: proof.generated
data: {"requestId":"abc123"}

event: provider.status
data: {"provider":"venice","circuitBreaker":"open"}

event: keepalive
data: {}
```

**Event Types:**

| Event | Description |
|-------|-------------|
| `request.started` | New request received |
| `request.completed` | Request completed successfully |
| `request.failed` | Request failed |
| `proof.generated` | Discharge proof created |
| `provider.status` | Provider circuit breaker state change |
| `keepalive` | Periodic keepalive (every 30s) |

---

### Metrics

```
GET /metrics
```

Prometheus-format metrics.

**Response:**
```
# HELP straylight_requests_total Total requests processed
# TYPE straylight_requests_total counter
straylight_requests_total{provider="venice"} 1234
straylight_requests_total{provider="openrouter"} 567

# HELP straylight_request_latency_seconds Request latency
# TYPE straylight_request_latency_seconds histogram
straylight_request_latency_seconds_bucket{le="0.1"} 100
straylight_request_latency_seconds_bucket{le="0.5"} 500
straylight_request_latency_seconds_bucket{le="1.0"} 800

# HELP straylight_circuit_breaker_state Circuit breaker state
# TYPE straylight_circuit_breaker_state gauge
straylight_circuit_breaker_state{provider="venice",state="closed"} 1
```

---

## Error Responses

Errors follow the OpenAI error format:

```json
{
  "error": {
    "message": "Invalid model: xyz",
    "type": "invalid_request_error",
    "param": "model",
    "code": "model_not_found"
  }
}
```

**HTTP Status Codes:**

| Code | Description |
|------|-------------|
| 200 | Success |
| 400 | Bad request (invalid parameters) |
| 401 | Unauthorized (if auth enabled) |
| 404 | Not found (invalid endpoint or proof) |
| 429 | Rate limited |
| 500 | Internal server error |
| 502 | All providers failed |
| 503 | Service unavailable (all circuit breakers open) |

---

## Rate Limits

straylight-llm applies configurable rate limits:

- **Per-IP**: 100 requests/minute (configurable)
- **Global**: 1000 requests/minute (configurable)

Rate limit headers:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1687882500
```
