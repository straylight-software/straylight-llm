# Configuration Guide

straylight-llm is configured via environment variables. No configuration files are required.

## Environment Variables

### Server Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `STRAYLIGHT_PORT` | HTTP port to listen on | `8080` |
| `STRAYLIGHT_HOST` | Host to bind to | `0.0.0.0` |
| `STRAYLIGHT_LOG_LEVEL` | Log verbosity (debug/info/warn/error) | `info` |

### Provider API Keys

Configure one or more providers. Requests will fall back through providers in order until one succeeds.

| Variable | Provider | Notes |
|----------|----------|-------|
| `VENICE_API_KEY` | Venice AI | Primary provider, uses Venice credits |
| `VERTEX_API_KEY` | Google Vertex AI | Requires `VERTEX_PROJECT` |
| `VERTEX_PROJECT` | GCP Project ID | Required for Vertex AI |
| `VERTEX_REGION` | GCP Region | Default: `us-central1` |
| `BASETEN_API_KEY` | Baseten | For self-hosted models |
| `OPENROUTER_API_KEY` | OpenRouter | Broad model access, good fallback |
| `ANTHROPIC_API_KEY` | Anthropic | Direct Claude access |

### Provider Fallback Order

Providers are tried in this order:

1. **Venice AI** — If `VENICE_API_KEY` is set
2. **Vertex AI** — If `VERTEX_API_KEY` and `VERTEX_PROJECT` are set
3. **Baseten** — If `BASETEN_API_KEY` is set
4. **OpenRouter** — If `OPENROUTER_API_KEY` is set
5. **Anthropic** — If `ANTHROPIC_API_KEY` is set

Only providers with configured API keys are included in the fallback chain.

### Resilience Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `STRAYLIGHT_MAX_RETRIES` | Max retries per provider | `3` |
| `STRAYLIGHT_RETRY_DELAY_MS` | Initial retry delay | `100` |
| `STRAYLIGHT_CIRCUIT_THRESHOLD` | Failures before circuit opens | `5` |
| `STRAYLIGHT_CIRCUIT_TIMEOUT_S` | Seconds before retry | `30` |
| `STRAYLIGHT_REQUEST_TIMEOUT_S` | Per-request timeout | `60` |

### Cache Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `STRAYLIGHT_PROOF_CACHE_SIZE` | Max cached proofs | `10000` |
| `STRAYLIGHT_PROOF_CACHE_TTL_S` | Proof cache TTL | `3600` |

### ClickHouse Telemetry

Export metrics to ClickHouse for dashboarding and historical analysis.

| Variable | Description | Default |
|----------|-------------|---------|
| `CLICKHOUSE_ENABLED` | Enable ClickHouse export | `false` |
| `CLICKHOUSE_HOST` | ClickHouse hostname | `localhost` |
| `CLICKHOUSE_PORT` | ClickHouse HTTP port | `8123` |
| `CLICKHOUSE_DATABASE` | Database name | `straylight` |
| `CLICKHOUSE_USER` | Username (optional) | — |
| `CLICKHOUSE_PASSWORD` | Password (optional) | — |
| `CLICKHOUSE_TLS` | Use HTTPS connection | `false` |

When enabled, the gateway exports:
- **metrics_snapshots** — Global stats every 10 seconds (requests, latency percentiles, error rate)
- **provider_metrics** — Per-provider stats (auth errors, rate limits, timeouts, avg latency)
- **requests** — Individual request logs (model, provider, latency, tokens, status)

## Example Configurations

### Minimal (OpenRouter Only)

```bash
export OPENROUTER_API_KEY=sk-or-v1-abc123...
./straylight-llm
```

### Production (Multi-Provider)

```bash
# Primary provider
export VENICE_API_KEY=vn-abc123...

# Secondary (GCP)
export VERTEX_API_KEY=ya29.abc123...
export VERTEX_PROJECT=my-gcp-project
export VERTEX_REGION=us-central1

# Fallbacks
export OPENROUTER_API_KEY=sk-or-v1-abc123...
export ANTHROPIC_API_KEY=sk-ant-api03-abc123...

# Server config
export STRAYLIGHT_PORT=8080
export STRAYLIGHT_LOG_LEVEL=info

# Resilience
export STRAYLIGHT_MAX_RETRIES=3
export STRAYLIGHT_CIRCUIT_THRESHOLD=5

./straylight-llm
```

### Docker Compose

```yaml
version: '3.8'
services:
  straylight-llm:
    image: straylight-llm:latest
    ports:
      - "8080:8080"
    environment:
      - OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - STRAYLIGHT_LOG_LEVEL=info
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### NixOS with Agenix Secrets

```nix
{ config, inputs, ... }: {
  imports = [ inputs.straylight-llm.nixosModules.default ];
  
  age.secrets.openrouter-api-key.file = ./secrets/openrouter-api-key.age;
  age.secrets.anthropic-api-key.file = ./secrets/anthropic-api-key.age;
  
  services.straylight-llm = {
    enable = true;
    port = 8080;
    
    environmentFile = config.age.secrets.openrouter-api-key.path;
    
    extraEnvironment = {
      STRAYLIGHT_LOG_LEVEL = "info";
      STRAYLIGHT_MAX_RETRIES = "3";
    };
  };
}
```

## Model Mapping

straylight-llm automatically maps OpenAI model names to provider-specific models:

| Request Model | Venice | Vertex | OpenRouter | Anthropic |
|--------------|--------|--------|------------|-----------|
| `gpt-4` | `llama-3.1-405b` | `gemini-1.5-pro` | `openai/gpt-4` | `claude-3-opus` |
| `gpt-4-turbo` | `llama-3.1-405b` | `gemini-1.5-pro` | `openai/gpt-4-turbo` | `claude-3-opus` |
| `gpt-3.5-turbo` | `llama-3.1-70b` | `gemini-1.5-flash` | `openai/gpt-3.5-turbo` | `claude-3-sonnet` |
| `claude-3-opus` | — | — | `anthropic/claude-3-opus` | `claude-3-opus-20240229` |

You can also specify provider-native model names directly.

## Verifying Configuration

```bash
# Check health and provider status
curl http://localhost:8080/health | jq

# Expected output:
{
  "status": "healthy",
  "providers": [
    {"name": "venice", "status": "available"},
    {"name": "openrouter", "status": "available"}
  ],
  "circuitBreakers": {
    "venice": "closed",
    "openrouter": "closed"
  }
}
```

## Troubleshooting

### "No providers configured"

At least one `*_API_KEY` environment variable must be set.

### "All providers failed"

Check:
1. API keys are valid
2. Network connectivity to provider endpoints
3. Circuit breaker status via `/health`

### "Circuit breaker open"

A provider has failed repeatedly. Wait for `STRAYLIGHT_CIRCUIT_TIMEOUT_S` seconds or restart the gateway.

### Provider-specific Issues

- **Venice**: Ensure your Venice account has credits
- **Vertex**: Ensure `VERTEX_PROJECT` is set and the service account has `aiplatform.endpoints.predict` permission
- **Anthropic**: Ensure you're using an API key (starts with `sk-ant-`)
