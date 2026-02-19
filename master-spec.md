# // straylight-llm master-spec //

LiteLLM-style OpenAI-compatible proxy with provider fallback chain. Runs inside `nix2gpu` containers via `nimi`.

______________________________________________________________________

## // project identity //

- **name**: `straylight-llm`
- **tagline**: OpenAI-compatible LLM gateway with provider fallback
- **license**: MIT
- **repo**: `github:weyl-ai/straylight-llm`

______________________________________________________________________

## // what this is //

`straylight-llm` is a **lightweight Haskell proxy** (~10 modules) that:

1. exposes an **OpenAI-compatible API** (`/v1/chat/completions`, `/v1/models`, etc.)
2. routes requests through a **provider fallback chain**:
   - **Venice AI** (primary) — use Venice credits first
   - **Vertex AI (GCP)** (secondary) — use GCP credits second
   - **Baseten** (tertiary) — fall back to Baseten third
   - **OpenRouter** (final fallback) — only if all others fail
3. transparently proxies streaming (SSE) and non-streaming responses
4. handles provider-specific auth (Bearer tokens, OAuth for Vertex)
5. runs as a containerized service via nimi/nix2gpu

this is **NOT** an AI agent server. it is a simple **LiteLLM-style proxy** that makes any client compatible with multiple LLM providers.

______________________________________________________________________

## // architecture overview //

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────┐
│   any client    │    │  straylight-llm │    │   LLM providers     │
│   (opencode,    │───▶│   proxy         │───▶│                     │
│    langchain,   │    │   :8080         │    │  ┌───────────────┐  │
│    curl, etc.)  │◀───│                 │◀───│  │ Venice AI     │  │
└─────────────────┘    └─────────────────┘    │  │ (primary)     │  │
                                              │  └───────────────┘  │
                                              │  ┌───────────────┐  │
                                              │  │ Vertex AI     │  │
                                              │  │ (secondary)   │  │
                                              │  └───────────────┘  │
                                              │  ┌───────────────┐  │
                                              │  │ Baseten       │  │
                                              │  │ (tertiary)    │  │
                                              │  └───────────────┘  │
                                              │  ┌───────────────┐  │
                                              │  │ OpenRouter    │  │
                                              │  │ (fallback)    │  │
                                              │  └───────────────┘  │
                                              └─────────────────────┘
```

**fallback logic:**

```
request arrives
  │
  ├─ try Venice AI
  │   ├─ success → return response
  │   ├─ auth/invalid error → fail immediately
  │   └─ rate limit/quota/unavailable → try next
  │
  ├─ try Vertex AI
  │   ├─ success → return response
  │   ├─ auth/invalid error → fail immediately
  │   └─ rate limit/quota/unavailable → try next
  │
  ├─ try Baseten
  │   ├─ success → return response
  │   ├─ auth/invalid error → fail immediately
  │   └─ rate limit/quota/unavailable → try next
  │
  └─ try OpenRouter (final)
      ├─ success → return response
      └─ any error → fail with error
```

______________________________________________________________________

## // tech stack //

| layer             | choice                 | rationale                                    |
|-------------------|------------------------|----------------------------------------------|
| language          | Haskell (GHC2021)      | type safety, servant API types, performance  |
| http framework    | servant + warp         | type-level API, compile-time route checking  |
| http client       | http-client-tls        | streaming, connection pooling                |
| config            | environment variables  | 12-factor app, container-friendly            |
| nix integration   | nix2gpu + nimi         | reproducible container, process management   |
| sensenet          | nix-compile infra      | Straylight stack integration                 |

**no** database. **no** sessions. **no** tools. just a simple proxy.

______________________________________________________________________

## // directory structure //

```
straylight-llm/
├── flake.nix                          # flake-parts entry point
├── flake.lock
├── LICENSE
├── README.md
├── master-spec.md                     # this file
│
├── dev/
│   └── flake-module.nix               # dev shell configuration
│
├── examples/
│   ├── basic.nix                      # minimal container (port 8080)
│   └── with-cgp.nix                   # container with secret file mounts
│
├── services/
│   └── straylight-gateway.nix         # nimi modular service definition
│
└── gateway/                           # // haskell source code //
    ├── straylight-llm.cabal           # cabal file with 10 modules
    ├── package.nix                    # nix derivation
    ├── LICENSE
    │
    ├── app/
    │   └── Main.hs                    # warp entry point
    │
    └── src/
        ├── Api.hs                     # servant API types
        ├── Config.hs                  # env var configuration
        ├── Handlers.hs                # request handlers
        ├── Router.hs                  # fallback chain logic
        ├── Types.hs                   # OpenAI-compatible types
        │
        └── Provider/
            ├── Types.hs               # Provider typeclass
            ├── Venice.hs              # Venice AI backend
            ├── Vertex.hs              # Vertex AI backend (OAuth)
            ├── Baseten.hs             # Baseten backend
            └── OpenRouter.hs          # OpenRouter backend
```

______________________________________________________________________

## // api endpoints //

| method | endpoint              | description                    |
|--------|-----------------------|--------------------------------|
| GET    | /health               | health check                   |
| POST   | /v1/chat/completions  | chat completion (streaming ok) |
| POST   | /v1/completions       | legacy completion               |
| POST   | /v1/embeddings        | generate embeddings            |
| GET    | /v1/models            | list available models          |

all endpoints follow the **OpenAI API specification**.

______________________________________________________________________

## // providers //

### Venice AI (primary)

- **URL**: `https://api.venice.ai/api/v1`
- **Auth**: Bearer token (`VENICE_API_KEY`)
- **Format**: OpenAI-compatible
- **Models**: llama-3.3-70b, deepseek-r1, qwen-2.5-coder, etc.

### Vertex AI (secondary)

- **URL**: `https://{location}-aiplatform.googleapis.com/v1/projects/{project}/locations/{location}/endpoints/openapi`
- **Auth**: Google Cloud OAuth (ADC or service account)
- **Format**: OpenAI-compatible
- **Models**: gemini-2.0-flash, gemini-1.5-pro, claude-3-5-sonnet (Model Garden)

### Baseten (tertiary)

- **URL**: `https://inference.baseten.co/v1`
- **Auth**: Api-Key header (`BASETEN_API_KEY`)
- **Format**: OpenAI-compatible
- **Models**: Account-specific model deployments

### OpenRouter (final fallback)

- **URL**: `https://openrouter.ai/api/v1`
- **Auth**: Bearer token (`OPENROUTER_API_KEY`)
- **Format**: OpenAI-compatible
- **Models**: 100+ models from multiple providers

______________________________________________________________________

## // environment variables //

| variable                      | description                          | required |
|-------------------------------|--------------------------------------|----------|
| STRAYLIGHT_PORT               | Server port (default: 8080)          | no       |
| STRAYLIGHT_HOST               | Server host (default: 0.0.0.0)       | no       |
| STRAYLIGHT_LOG_LEVEL          | Log level (default: info)            | no       |
| VENICE_API_KEY                | Venice AI API key                    | no*      |
| VENICE_API_KEY_FILE           | Path to Venice API key file          | no       |
| GOOGLE_CLOUD_PROJECT          | GCP project ID for Vertex AI         | no*      |
| VERTEX_LOCATION               | Vertex AI location (default: us-central1) | no  |
| GOOGLE_APPLICATION_CREDENTIALS| Path to GCP service account key      | no       |
| BASETEN_API_KEY               | Baseten API key                      | no*      |
| BASETEN_API_KEY_FILE          | Path to Baseten API key file         | no       |
| OPENROUTER_API_KEY            | OpenRouter API key                   | no*      |
| OPENROUTER_API_KEY_FILE       | Path to OpenRouter API key file      | no       |

*at least one provider must be configured

______________________________________________________________________

## // services/straylight-gateway.nix //

nimi modular service definition (curried function pattern):

```nix
{ pkgs, ... }:
{ lib, config, ... }:
let
  cfg = config.straylightGateway;

  straylightPackage = pkgs.callPackage ../gateway/package.nix { };

  secretLoader = pkgs.writeShellApplication {
    name = "straylight-load-secrets";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # Load Venice API key
      if [[ -n "''${VENICE_API_KEY_FILE:-}" ]] && [[ -f "$VENICE_API_KEY_FILE" ]]; then
        export VENICE_API_KEY
        VENICE_API_KEY="$(cat "$VENICE_API_KEY_FILE")"
      fi
      # Load Baseten API key
      if [[ -n "''${BASETEN_API_KEY_FILE:-}" ]] && [[ -f "$BASETEN_API_KEY_FILE" ]]; then
        export BASETEN_API_KEY
        BASETEN_API_KEY="$(cat "$BASETEN_API_KEY_FILE")"
      fi
      # Load OpenRouter API key
      if [[ -n "''${OPENROUTER_API_KEY_FILE:-}" ]] && [[ -f "$OPENROUTER_API_KEY_FILE" ]]; then
        export OPENROUTER_API_KEY
        OPENROUTER_API_KEY="$(cat "$OPENROUTER_API_KEY_FILE")"
      fi
      exec "$@"
    '';
  };

  wrapper = pkgs.writeShellApplication {
    name = "straylight-gateway";
    runtimeInputs = [ straylightPackage secretLoader pkgs.google-cloud-sdk ];
    runtimeEnv = { }
      // lib.optionalAttrs (cfg.venice.apiKeyFile != null) {
        VENICE_API_KEY_FILE = cfg.venice.apiKeyFile;
      }
      // lib.optionalAttrs (cfg.baseten.apiKeyFile != null) {
        BASETEN_API_KEY_FILE = cfg.baseten.apiKeyFile;
      }
      // lib.optionalAttrs (cfg.openrouter.apiKeyFile != null) {
        OPENROUTER_API_KEY_FILE = cfg.openrouter.apiKeyFile;
      }
      // lib.optionalAttrs (cfg.vertex.projectId != null) {
        GOOGLE_CLOUD_PROJECT = cfg.vertex.projectId;
      }
      // cfg.environmentVariables;
    text = ''
      straylight-load-secrets straylight-llm "$@"
    '';
  };
in
{
  _class = "service";

  options.straylightGateway = {
    enable = lib.mkEnableOption "straylight-llm gateway service";

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
    };

    venice.apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/venice-api-key";
    };

    vertex.projectId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "my-gcp-project";
    };

    baseten.apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/baseten-api-key";
    };

    openrouter.apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/openrouter-api-key";
    };

    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    process.argv = [ (lib.getExe wrapper) ];
  };
}
```

______________________________________________________________________

## // building //

```bash
# build the haskell binary
nix build .#straylight-llm

# build the container image
nix build .#basic

# run locally
./result/bin/straylight-llm

# load and run container
docker load < result
docker run -p 8080:8080 \
  -e OPENROUTER_API_KEY="sk-or-..." \
  straylight-llm-basic:latest
```

______________________________________________________________________

## // usage examples //

### curl

```bash
# Chat completion
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.3-70b",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# List models
curl http://localhost:8080/v1/models
```

### Python (OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8080/v1",
    api_key="dummy"  # Not used by proxy
)

response = client.chat.completions.create(
    model="llama-3.3-70b",
    messages=[{"role": "user", "content": "Hello!"}]
)
print(response.choices[0].message.content)
```

______________________________________________________________________

## // sensenet integration //

straylight-llm integrates with the sensenet flake for nix-compile infrastructure:

```nix
inputs.sensenet = {
  url = "github:straylight-software/sensenet/nix-compile/strict-straylight";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

This provides:
- LLVM/CUDA build infrastructure
- TensorRT integration for local inference
- Shared nixpkgs for reproducibility

______________________________________________________________________

## // future work //

- [ ] Streaming SSE proxy (passthrough from providers)
- [ ] Request/response logging for observability
- [ ] Token counting and cost tracking
- [ ] Model aliasing (e.g., "gpt-4" → "llama-3.3-70b")
- [ ] Rate limiting and request queuing
- [ ] Health checks for individual providers
- [ ] Prometheus metrics endpoint
