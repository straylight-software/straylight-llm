# Quick Start Guide

This guide will get you running straylight-llm in under 5 minutes.

## Prerequisites

1. **Nix with flakes enabled**
   ```bash
   # Install Nix (if not already installed)
   curl -L https://nixos.org/nix/install | sh
   
   # Enable flakes (add to ~/.config/nix/nix.conf)
   experimental-features = nix-command flakes
   ```

2. **At least one API key** — OpenRouter is recommended for getting started:
   - Sign up at https://openrouter.ai
   - Get your API key from the dashboard

## Installation

### Option 1: Run from Source

```bash
# Clone the repository
git clone https://github.com/justinfleek/straylight-llm.git
cd straylight-llm

# Enter the development shell
nix develop

# Build and run
cd gateway
OPENROUTER_API_KEY=sk-or-... cabal run straylight-llm
```

### Option 2: Run Container

```bash
# Build the container
nix build .#straylight-llm

# Run with Docker
docker load < result
docker run -p 8080:8080 \
  -e OPENROUTER_API_KEY=sk-or-... \
  straylight-llm:latest
```

### Option 3: NixOS Module

```nix
# In your flake.nix
{
  inputs.straylight-llm.url = "github:justinfleek/straylight-llm";
}

# In your configuration.nix
{ inputs, ... }: {
  imports = [ inputs.straylight-llm.nixosModules.default ];
  
  services.straylight-llm = {
    enable = true;
    port = 8080;
    openrouterApiKey = "sk-or-...";  # Or use agenix for secrets
  };
}
```

## Verify Installation

```bash
# Health check
curl http://localhost:8080/health
# Expected: {"status":"healthy","providers":[...]}

# List available models
curl http://localhost:8080/v1/models
```

## Your First Request

```bash
# Simple chat completion
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {"role": "user", "content": "What is 2 + 2?"}
    ]
  }'
```

## Streaming

```bash
# Streaming response (Server-Sent Events)
curl -X POST http://localhost:8080/v1/chat/completions/stream \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {"role": "user", "content": "Tell me a short story"}
    ]
  }'
```

## Next Steps

- [Configuration Guide](./CONFIGURATION.md) — Set up multiple providers
- [API Reference](./API_REFERENCE.md) — Full endpoint documentation
- [Deployment Guide](./DEPLOYMENT.md) — Production deployment
- [Architecture](./ARCHITECTURE.md) — How it works under the hood
