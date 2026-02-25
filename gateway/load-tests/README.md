# Load Tests

k6 load testing scripts for straylight-llm gateway.

## Prerequisites

Install k6:

```bash
# macOS
brew install k6

# Linux (Debian/Ubuntu)
sudo apt install k6

# Or via nix
nix-shell -p k6
```

## Available Tests

### chat-completions.js
Tests the `/v1/chat/completions` endpoint with various payload sizes.

**Scenarios:**
- `smoke`: Basic functionality (1 VU, 10s)
- `load`: Normal production load (10-50 VUs, ramping)
- `stress`: Find breaking points (100-200 VUs)

```bash
# Quick smoke test
k6 run chat-completions.js --scenario smoke

# Full load test
k6 run chat-completions.js

# Custom configuration
k6 run --vus 50 --duration 30s chat-completions.js
```

### streaming.js
Tests streaming responses via SSE.

**Scenarios:**
- `sustained_streaming`: 10 concurrent streams for 2 minutes
- `burst_streaming`: Burst to 50 concurrent streams

```bash
k6 run streaming.js
```

### embeddings.js
Tests the `/v1/embeddings` endpoint with high throughput.

**Scenarios:**
- `throughput`: 100 RPS constant rate
- `batch_processing`: Batch embedding requests

```bash
k6 run embeddings.js
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_URL` | `http://localhost:8080` | Gateway base URL |
| `API_KEY` | `test-key` | API key for authentication |

Example:

```bash
k6 run --env BASE_URL=http://gateway.example.com --env API_KEY=sk-xxx chat-completions.js
```

## Output

### Console Summary
Default k6 output shows request stats, latency percentiles, and threshold results.

### JSON Output
```bash
k6 run --out json=results.json chat-completions.js
```

### InfluxDB (for Grafana dashboards)
```bash
k6 run --out influxdb=http://localhost:8086/k6 chat-completions.js
```

## Performance Targets

| Metric | Target | Description |
|--------|--------|-------------|
| `http_req_duration p(95)` | < 500ms | 95th percentile latency |
| `http_req_duration p(99)` | < 1000ms | 99th percentile latency |
| `http_req_failed` | < 1% | HTTP error rate |
| `ttfb_stream_ms p(95)` | < 200ms | Time to first byte (streaming) |
| `embedding_latency_ms p(95)` | < 100ms | Embedding latency |

## Development

To run against a local dev server:

```bash
# Terminal 1: Start gateway
nix develop --command bash -c "cd gateway && cabal run straylight-llm"

# Terminal 2: Run tests
cd gateway/load-tests
k6 run chat-completions.js --scenario smoke
```
