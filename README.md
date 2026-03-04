# straylight-llm

[![Build](https://github.com/straylight-software/straylight-llm/actions/workflows/build-container.yml/badge.svg)](https://github.com/straylight-software/straylight-llm/actions)
[![Tests](https://img.shields.io/badge/tests-377%20passing-brightgreen)]()
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**OpenAI-compatible LLM gateway with provider fallback, effect tracking, and formal verification.**

A production-grade Haskell gateway that routes LLM requests through multiple providers with automatic failover, circuit breakers, and cryptographic discharge proofs for every request.

## Why straylight-llm?

| Feature | straylight-llm | LiteLLM | OpenRouter |
|---------|---------------|---------|------------|
| **Self-hosted** | Yes | Yes | No |
| **Formal verification** | Lean4 proofs | No | No |
| **Discharge proofs** | Ed25519 signed | No | No |
| **Effect tracking** | Graded monads | No | No |
| **io_uring backend** | Yes (5x throughput) | No | N/A |
| **Circuit breakers** | Per-provider | Limited | N/A |
| **Language** | Haskell | Python | N/A |
| **Binary protocol** | SIGIL over ZMQ | No | No |

**straylight-llm** is for teams who need:
- Cryptographic proof that requests were handled correctly
- Verifiable security guarantees (not just "trust us")
- Maximum throughput with minimal latency
- Self-hosted control over their AI infrastructure

## Features

- **OpenAI-compatible API** — Drop-in replacement for OpenAI client libraries
- **Multi-provider fallback** — Venice AI → Vertex AI → Baseten → OpenRouter → Anthropic
- **Circuit breakers** — Automatic provider isolation on failures
- **Streaming SSE** — Real-time token streaming with `text/event-stream`
- **SIGIL transport** — Binary wire protocol over ZMQ (eliminates JSON parsing in clients)
- **Discharge proofs** — Ed25519-signed cryptographic proofs for every request
- **Effect tracking** — Graded monad system tracks all IO effects
- **Formal verification** — 904 lines of Lean4 proofs (no `sorry`, no axioms)
- **Prometheus metrics** — `/metrics` endpoint for observability
- **OpenTelemetry tracing** — Distributed tracing with configurable OTLP export
- **Rate limiting** — Per-API-key token bucket rate limiting
- **Response caching** — Configurable LRU cache with TTL
- **377 tests** — Property tests, integration tests, adversarial tests, formal correspondence tests

## Quick Start

### Using Nix (recommended)

```bash
# Development shell
nix develop

# Build
nix build .#straylight-llm

# Run
./result/bin/straylight-llm
```

### Using Cabal

```bash
cd gateway
cabal build
cabal run straylight-llm
```

### Docker

```bash
# Build container
nix build .#production

# Or pull from GHCR
docker pull ghcr.io/straylight-software/straylight-llm:latest
```

## Configuration

Configure via environment variables:

### Core Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Server port | `8080` |
| `HOST` | Bind address | `0.0.0.0` |
| `LOG_LEVEL` | Logging level (`debug`, `info`, `warn`, `error`) | `info` |
| `REQUEST_TIMEOUT` | Request timeout in seconds | `120` |
| `MAX_RETRIES` | Max retry attempts per provider | `3` |

### Observability

| Variable | Description | Default |
|----------|-------------|---------|
| `OTEL_ENABLED` | Enable OpenTelemetry tracing | `false` |
| `OTEL_ENDPOINT` | OTLP exporter endpoint | `http://localhost:4317` |
| `OTEL_SERVICE_NAME` | Service name for traces | `straylight-llm` |

### Rate Limiting

| Variable | Description | Default |
|----------|-------------|---------|
| `RATE_LIMIT_ENABLED` | Enable rate limiting | `false` |
| `RATE_LIMIT_RPM` | Requests per minute per API key | `60` |
| `RATE_LIMIT_BURST` | Burst allowance above RPM | `10` |

### Response Cache

| Variable | Description | Default |
|----------|-------------|---------|
| `CACHE_ENABLED` | Enable response caching | `true` |
| `CACHE_MAX_SIZE` | Maximum cached entries | `10000` |
| `CACHE_TTL_SECONDS` | Cache entry TTL | `300` |

### Connection Pool

| Variable | Description | Default |
|----------|-------------|---------|
| `POOL_CONNECTIONS_PER_HOST` | Max connections per upstream host | `100` |
| `POOL_IDLE_CONNECTIONS` | Max idle connections total | `200` |
| `POOL_IDLE_TIMEOUT_SECONDS` | Idle connection timeout | `60` |

### Provider Configuration

Each provider reads its API key from a file path for security:

| Variable | Description |
|----------|-------------|
| `VENICE_API_KEY_PATH` | Path to Venice AI API key file |
| `VENICE_ENABLED` | Enable Venice provider (`true`/`false`) |
| `VERTEX_PROJECT_ID` | GCP project ID for Vertex AI |
| `VERTEX_LOCATION` | Vertex AI region (e.g., `us-central1`) |
| `VERTEX_SERVICE_ACCOUNT_KEY_PATH` | Path to GCP service account JSON |
| `BASETEN_API_KEY_PATH` | Path to Baseten API key file |
| `OPENROUTER_API_KEY_PATH` | Path to OpenRouter API key file |
| `ANTHROPIC_API_KEY_PATH` | Path to Anthropic API key file |

## API Endpoints

### Chat Completions

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Streaming

```bash
curl -X POST http://localhost:8080/v1/chat/completions/stream \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Hello!"}],
    "stream": true
  }'
```

### Embeddings

```bash
curl -X POST http://localhost:8080/v1/embeddings \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "text-embedding-ada-002",
    "input": "Hello world"
  }'
```

### Models

```bash
curl http://localhost:8080/v1/models
```

### Health Check

```bash
curl http://localhost:8080/health
```

### Prometheus Metrics

```bash
curl http://localhost:8080/metrics
```

Returns Prometheus text format with request counts, latencies, provider status, and rate limiter stats.

### Discharge Proofs

Retrieve the cryptographic proof for a completed request:

```bash
curl http://localhost:8080/v1/proof/{request_id}
```

### Real-time Events (SSE)

Subscribe to real-time gateway events:

```bash
curl http://localhost:8080/v1/events
```

Event types: `request.started`, `request.completed`, `proof.generated`, `provider.status`, `keepalive`

## Provider Priority

Requests are routed through providers in order until one succeeds:

1. **Venice AI** — Primary (use Venice credits first)
2. **Vertex AI** — Secondary (GCP credits)
3. **Baseten** — Tertiary
4. **OpenRouter** — Fallback
5. **Anthropic** — Direct Anthropic API

Each provider has an independent circuit breaker. Failed providers are temporarily removed from rotation.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     straylight-llm                          │
├─────────────────────────────────────────────────────────────┤
│  Request → Router → Provider Chain → Response               │
│              │                                              │
│              ├── Circuit Breakers (per-provider)            │
│              ├── Retry Logic (configurable)                 │
│              ├── Effect Tracking (GatewayM monad)           │
│              └── Discharge Proofs (ed25519 signed)          │
├─────────────────────────────────────────────────────────────┤
│  Providers: Venice │ Vertex │ Baseten │ OpenRouter │ ...    │
├─────────────────────────────────────────────────────────────┤
│  SIGIL Transport: ZMQ PUB/SUB │ Binary frames │ No JSON     │
└─────────────────────────────────────────────────────────────┘
```

### SIGIL Transport Layer

For high-performance clients, straylight-llm exposes a SIGIL binary protocol over ZeroMQ:

- **ZMQ PUB** on port 5555 — Clients SUB to receive SIGIL frames
- **ZMQ ROUTER** on port 5556 — Request/response for non-streaming
- **No JSON parsing** — Clients receive pre-tokenized binary frames
- **Mode tracking** — Text/think/toolCall/codeBlock semantic modes

See [libevring/docs/sigil.md](libevring/docs/sigil.md) for the full protocol specification.

## Testing

```bash
cd gateway

# Run all tests (377 tests)
cabal test

# Run benchmarks
cabal bench
```

Test categories:
- **Property tests** — Types roundtrip, coeffect laws, graded monad laws
- **Integration tests** — API endpoints, proof generation, lifecycle
- **Adversarial tests** — Race conditions, injection attacks, provider errors
- **Formal tests** — Haskell ↔ Lean4 correspondence

## Formal Verification

The `proofs/` directory contains Lean4 proofs for critical invariants:

- `Straylight/Coeffect.lean` — Coeffect monoid laws, tensor product, discharge proofs
- `Straylight/Gateway.lean` — Provider types, fallback termination, retry bounds
- `Straylight/Hermetic.lean` — Hermeticity guarantees, cache isolation

All proofs compile without `sorry` or axiom escapes.

## NixOS Module

```nix
{
  imports = [ inputs.straylight-llm.nixosModules.default ];

  services.straylight-llm = {
    enable = true;
    port = 8080;
    providers = {
      venice.apiKeyFile = "/run/secrets/venice-api-key";
      vertex = {
        projectId = "my-gcp-project";
        location = "us-central1";
        serviceAccountKeyFile = "/run/secrets/gcp-sa.json";
      };
    };
  };
}
```

## Development

```bash
# Enter dev shell (includes GHC 9.12, cabal, haskell-language-server)
nix develop

# Build
cd gateway && cabal build

# Run tests
cabal test

# Format code
nix fmt

# Verify Dhall config
nix build .#dhall-verify
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — Technical deep dive, effect system, formal proofs
- [Deployment](docs/DEPLOYMENT.md) — Production deployment guide, systemd, Docker, NixOS
- [Roadmap](docs/ROADMAP.md) — Versioned feature plan

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

1. Ensure all 377 tests pass: `cd gateway && cabal test`
2. Run the formatter: `nix fmt`
3. Verify Dhall manifests: `nix build .#dhall-verify`
4. No partial functions (`head`, `tail`, `fromJust`, `read`, `!!`)
5. No `SomeException` — use specific exception types

See the [Roadmap](docs/ROADMAP.md) for planned features. Open an issue to discuss contributions.
