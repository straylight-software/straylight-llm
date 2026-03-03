# Deployment Guide

## Quick Start

```bash
# Build the binary
nix build .#straylight-llm

# Run directly
./result/bin/straylight-llm
```

## Configuration

All configuration via environment variables:

### Server Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Server port |
| `HOST` | `0.0.0.0` | Bind address |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` |
| `REQUEST_TIMEOUT` | `120` | Timeout in seconds |
| `MAX_RETRIES` | `3` | Retries per provider |

### Provider API Keys

Keys are read from **files** for security (never env vars directly):

| Variable | Description |
|----------|-------------|
| `VENICE_API_KEY_PATH` | Path to Venice AI key file |
| `OPENROUTER_API_KEY_PATH` | Path to OpenRouter key file |
| `ANTHROPIC_API_KEY_PATH` | Path to Anthropic key file |
| `BASETEN_API_KEY_PATH` | Path to Baseten key file |

### Vertex AI (GCP)

| Variable | Description |
|----------|-------------|
| `VERTEX_PROJECT_ID` | GCP project ID |
| `VERTEX_LOCATION` | Region (e.g., `us-central1`) |
| `VERTEX_SERVICE_ACCOUNT_KEY_PATH` | Path to service account JSON |

## Systemd Service

```ini
[Unit]
Description=straylight-llm gateway
After=network.target

[Service]
Type=simple
User=straylight
ExecStart=/opt/straylight-llm/bin/straylight-llm
Restart=always
RestartSec=5

# Security
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/straylight

# API keys
Environment=OPENROUTER_API_KEY_PATH=/run/secrets/openrouter
Environment=ANTHROPIC_API_KEY_PATH=/run/secrets/anthropic

[Install]
WantedBy=multi-user.target
```

## Docker / Podman

```bash
# Build container (requires CUDA for GPU containers)
nix build .#production

# Load and run
docker load < result
docker run -d \
  -p 8080:8080 \
  -v /path/to/secrets:/run/secrets:ro \
  -e OPENROUTER_API_KEY_PATH=/run/secrets/openrouter \
  ghcr.io/straylight-software/straylight-llm:latest
```

## NixOS Module

```nix
{
  imports = [ inputs.straylight-llm.nixosModules.default ];

  services.straylight-llm = {
    enable = true;
    port = 8080;
    
    providers = {
      openrouter.apiKeyFile = "/run/secrets/openrouter";
      anthropic.apiKeyFile = "/run/secrets/anthropic";
      
      vertex = {
        projectId = "my-gcp-project";
        location = "us-central1";
        serviceAccountKeyFile = "/run/secrets/gcp-sa.json";
      };
    };
  };
}
```

## Health Checks

```bash
# Basic health
curl http://localhost:8080/health

# Provider status
curl http://localhost:8080/v1/providers/status

# Metrics
curl http://localhost:8080/v1/metrics
```

## Monitoring

### Prometheus Metrics

The `/v1/metrics` endpoint exposes:
- `straylight_requests_total` - Total requests by provider/status
- `straylight_latency_seconds` - Request latency histogram
- `straylight_circuit_breaker_state` - Provider circuit breaker states
- `straylight_tokens_total` - Token usage by model

### Real-time Events (SSE)

```bash
curl http://localhost:8080/v1/events
```

Events: `request.started`, `request.completed`, `proof.generated`, `provider.status`

## Security Checklist

- [ ] API keys in files, not environment variables
- [ ] Files readable only by service user (`chmod 400`)
- [ ] Run as non-root user
- [ ] Use systemd hardening (`NoNewPrivileges`, `ProtectSystem`)
- [ ] TLS termination via reverse proxy (nginx, caddy)
- [ ] Rate limiting at load balancer level

## Provider Fallback Order

1. **Venice AI** (primary)
2. **Vertex AI** (GCP)
3. **Baseten**
4. **OpenRouter**
5. **Anthropic** (direct)

Each provider has independent circuit breakers. Failed providers are temporarily removed from rotation.

## Performance Tuning

### io_uring Backend

Set `USE_URING=1` for the high-performance io_uring backend:

```bash
USE_URING=1 ./result/bin/straylight-llm
```

Requires Linux 5.1+ with io_uring support.

### Recommended Settings

| Deployment | Workers | Timeout | Max Retries |
|------------|---------|---------|-------------|
| Development | 1 | 120s | 1 |
| Production | 4-8 | 60s | 3 |
| High-volume | 16+ | 30s | 2 |
