# // nix2llm master-spec //

lightweight openai-compatible llm gateway with cgp-first routing.
runs inside a `nix2gpu` container via `nimi`.

______________________________________________________________________

## // project identity //

- **name**: `nix2llm`
- **tagline**: cgp-first openai gateway for nix2gpu
- **license**: MIT
- **repo**: `github:weyl-ai/nix2llm`

______________________________________________________________________

## // what this is //

`nix2llm` is a **lightweight** openai-compatible proxy server that:

1. receives standard openai api requests (`/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`, `/v1/models`)
2. tries to route them to a **cgp** (cloud gpu provider) endpoint first — this is your local/weyl inference server running vllm, tgi, sglang, or any openai-compatible backend on gpu hardware
3. if the cgp is **unavailable** (connection refused, timeout, 5xx, or not configured), transparently **falls back** to openrouter
4. returns a standard openai response to the caller — the caller never knows which backend served the request

it is **not** litellm. it is ~2000 lines of python, zero database, zero redis, zero admin ui. it is a single async process that does one thing well: cgp-first routing with openrouter fallback.

______________________________________________________________________

## // architecture overview //

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   caller         │    │    nix2llm      │    │   backends      │
│   (any openai    │───▶│   gateway       │───▶│                 │
│    compatible     │    │   :4000         │    │  ┌───────────┐  │
│    client)        │◀───│                 │◀───│  │ cgp       │  │
└─────────────────┘    └─────────────────┘    │  │ (primary)  │  │
                                               │  └───────────┘  │
                                               │  ┌───────────┐  │
                                               │  │ openrouter │  │
                                               │  │ (fallback) │  │
                                               │  └───────────┘  │
                                               └─────────────────┘
```

**routing decision tree:**

```
request arrives
  │
  ├─ cgp configured?
  │   ├─ yes ──▶ forward to cgp
  │   │           ├─ success ──▶ return response
  │   │           └─ failure ──▶ forward to openrouter
  │   │                           ├─ success ──▶ return response
  │   │                           └─ failure ──▶ return error
  │   └─ no ───▶ forward to openrouter
  │               ├─ success ──▶ return response
  │               └─ failure ──▶ return error
  └─ done
```

______________________________________________________________________

## // tech stack //

| layer             | choice                 | rationale                                    |
|-------------------|------------------------|----------------------------------------------|
| language          | python 3.12+           | httpx async, first-class sse support         |
| http framework    | starlette + uvicorn    | minimal, async-native, zero magic            |
| http client       | httpx                  | async, streaming, connection pooling          |
| config            | pydantic-settings      | env var + file, typed, validated              |
| nix integration   | nix2gpu + nimi service  | reproducible container, process management    |
| packaging         | uv                     | fast, lockfile-based, reproducible            |

**no** database. **no** redis. **no** celery. **no** sqlalchemy. **no** admin ui. **no** virtual keys. **no** cost tracking. this is a proxy, not a platform.

______________________________________________________________________

## // directory structure //

follows `nix2gpu` conventions exactly. every nix module file gets `_class = "nix2llm"`.
module organization uses `import-tree` for auto-discovery.

```
nix2llm/
├── flake.nix                          # flake-parts entry point
├── flake.lock
├── LICENSE.md
├── README.md
├── book.toml                          # mdbook config
│
├── docs/
│   ├── SUMMARY.md
│   ├── index.md
│   ├── architecture.md
│   ├── getting-started.md
│   ├── configuration.md
│   └── services.md
│
├── dev/
│   ├── flake-parts.nix                # systems = import inputs.systems; debug = true;
│   ├── nixpkgs.nix                    # pkgs overlay config
│   ├── devshell.nix                   # dev dependencies
│   └── formatter.nix                  # treefmt-nix (nixfmt, shfmt, ruff, etc.)
│
├── checks/
│   └── all-files-have-lower-case-names.nix
│
├── modules/
│   ├── flake-module.nix               # perSystem.nix2llm option definition
│   ├── eval-nix2llm-module.nix        # lib.evalModules wrapper
│   ├── mk-nix2llm-container.nix       # nimi.mkContainerImage builder
│   └── nix2llm-module.nix             # flake.modules.nix2llm.default = import-tree ../nix2llm;
│
├── nix2llm/                           # // core nix module tree (auto-imported) //
│   ├── meta.nix
│   ├── name.nix
│   ├── tag.nix
│   ├── env.nix
│   ├── extra-env.nix
│   ├── extra-labels.nix
│   ├── labels.nix
│   ├── exposed-ports.nix
│   ├── system-packages.nix
│   ├── copy-to-root.nix
│   ├── working-dir.nix
│   ├── max-layers.nix
│   ├── registries.nix
│   ├── passthru.nix
│   ├── profile.nix
│   ├── scripts.nix
│   ├── services.nix
│   ├── extra-startup-script.nix
│   ├── startup-script.nix
│   ├── home.nix
│   ├── sshd.nix
│   ├── nix-config.nix
│   │
│   ├── gateway/                       # // nix2llm-specific modules //
│   │   ├── config.nix                 # gateway configuration options
│   │   ├── service.nix                # nimi service definition for the gateway
│   │   └── health.nix                 # health check configuration
│   │
│   ├── container/
│   │   ├── nimi-settings.nix
│   │   ├── types.nix
│   │   ├── nix-store-profile.nix
│   │   ├── config/
│   │   │   ├── nix.conf
│   │   │   └── sshd_config
│   │   └── identity/
│   │       ├── users.nix
│   │       ├── groups.nix
│   │       ├── passwd-contents.nix
│   │       ├── group-contents.nix
│   │       └── shadow-contents.nix
│   │
│   ├── base-system/
│   │   ├── default.nix
│   │   └── create-base-system.sh
│   │
│   ├── environment/
│   │   ├── core.nix
│   │   ├── dev.nix
│   │   └── network.nix
│   │
│   ├── home/
│   │   ├── _config.nix
│   │   ├── _bash/
│   │   ├── _starship/
│   │   └── _tmux/
│   │
│   ├── scripts/
│   │   ├── copy-to-container-runtime.nix
│   │   ├── copy-to-github.nix
│   │   └── shell.nix
│   │
│   └── startup-script/
│       └── startup.sh
│
├── services/
│   └── nix2llm-gateway.nix           # // nimi modular service module //
│
├── gateway/                           # // python source code //
│   ├── pyproject.toml
│   ├── uv.lock
│   └── src/
│       └── nix2llm/
│           ├── __init__.py
│           ├── __main__.py            # uvicorn entrypoint
│           ├── app.py                 # starlette application
│           ├── config.py              # pydantic-settings configuration
│           ├── router.py              # cgp-first routing logic
│           ├── providers/
│           │   ├── __init__.py
│           │   ├── base.py            # abstract provider interface
│           │   ├── cgp.py             # cloud gpu provider backend
│           │   └── openrouter.py      # openrouter fallback backend
│           ├── endpoints/
│           │   ├── __init__.py
│           │   ├── chat.py            # /v1/chat/completions
│           │   ├── completions.py     # /v1/completions
│           │   ├── embeddings.py      # /v1/embeddings
│           │   ├── models.py          # /v1/models
│           │   └── health.py          # /health, /ready
│           ├── middleware/
│           │   ├── __init__.py
│           │   ├── logging.py         # structured request/response logging
│           │   └── errors.py          # openai-compatible error responses
│           ├── streaming.py           # sse proxy for streaming responses
│           └── types.py               # request/response pydantic models
│
├── examples/
│   ├── basic.nix                      # minimal gateway container
│   ├── with-cgp.nix                   # gateway + cgp endpoint configured
│   └── with-tailscale.nix             # gateway + tailscale mesh networking
│
└── templates/
    └── basic/
        ├── flake.nix
        ├── flake.lock
        ├── default.nix
        └── README.md
```

______________________________________________________________________

## // flake.nix //

```nix
{
  description = "nix2llm - cgp-first openai gateway for nix2gpu containers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";

    systems.url = "github:nix-systems/x86_64-linux";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nimi = {
      url = "github:weyl-ai/nimi/baileylu/minimize-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix2container.follows = "nimi/nix2container";

    # // nix2gpu for base container modules //
    nix2gpu = {
      url = "github:fleek-sh/nix2gpu";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.systems.follows = "systems";
    };
  };

  nixConfig = {
    extra-substituters = [ "https://weyl-ai.cachix.org" ];
    extra-trusted-public-keys = [
      "weyl-ai.cachix.org-1:cR0SpSAPw7wejZ21ep4SLojE77gp5F2os260eEWqTTw="
    ];
  };

  outputs =
    { flake-parts, import-tree, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (import-tree [
      ./examples
      ./dev
      ./checks
      ./modules
    ]);
}
```

______________________________________________________________________

## // nix module patterns //

every nix file in `nix2llm/` follows these exact conventions from `nix2gpu`:

### module class

```nix
# every module in nix2llm/ sets _class
{
  _class = "nix2llm";
  # ... rest of module
}
```

### option definitions

```nix
# pattern: outer function receives lib/pkgs, defines options + config
{ lib, config, pkgs, ... }:
let
  inherit (lib) types mkOption literalExpression;
in
{
  _class = "nix2llm";

  options.myOption = mkOption {
    description = ''
      multi-line description of the option.

      include usage context, what it does, and when to change it.
    '';
    example = literalExpression ''
      myOption = "value";
    '';
    type = types.str;
    default = "default-value";
  };

  config.nimiSettings.container.imageConfig.SomeField = config.myOption;
}
```

### service definitions

```nix
# pattern: curried function — outer receives pkgs, inner receives config
{ pkgs, ... }:
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.nix2llmGateway;
in
{
  _class = "service";

  options.nix2llmGateway = {
    # option definitions
  };

  config.process.argv = [ (lib.getExe wrapper) ];
}
```

### startup scripts

```nix
# pattern: resholve for shell safety, gum for logging
config.nimiSettings.startup.runOnStartup = lib.getExe (
  pkgs.resholve.writeScriptBin "${name}-startup.sh"
    {
      interpreter = lib.getExe pkgs.bash;
      inputs = config.systemPackages ++ [ extraStartupScript ];
      # ... resholve config
    }
    ''
      ${builtins.readFile ./startup-script/startup.sh}
      extra-startup-script
    ''
);
```

### comment style

```nix
# // section name // description
gum log --level debug "Container initialization starting..."
```

```bash
# // critical // runtime directories
mkdir -p /tmp /var/tmp /run
```

______________________________________________________________________

## // modules/flake-module.nix //

```nix
{ config, ... }:
let
  nix2llmSourceCfg = config;

  flakeModule =
    { lib, flake-parts-lib, ... }:
    let
      inherit (flake-parts-lib) mkPerSystemOption;
      inherit (lib) mkOption types;
    in
    {
      options.perSystem = mkPerSystemOption {
        options.nix2llm = mkOption {
          description = ''
            `nix2llm` is a lightweight openai-compatible llm gateway with
            cgp-first routing, designed to run inside `nix2gpu` containers.

            it routes requests to a cloud gpu provider (cgp) first, then
            falls back to openrouter when the cgp is unavailable.

            key features:
            - **openai-compatible**: drop-in replacement for any openai client
            - **cgp-first routing**: prioritize your own gpu inference
            - **openrouter fallback**: automatic failover to openrouter
            - **streaming support**: full sse proxy for streaming responses
            - **zero dependencies**: no database, no redis, no admin ui
          '';
          type = types.lazyAttrsOf types.raw;
        };
      };

      config.perSystem =
        { system, config, ... }:
        let
          inherit (nix2llmSourceCfg.allSystems.${system}) mkNix2LlmContainer;
          generatedPkgs = lib.mapAttrs mkNix2LlmContainer config.nix2llm;
        in
        {
          packages = generatedPkgs;
          checks = generatedPkgs;
        };
    };
in
{
  imports = [ flakeModule ];
  flake = { inherit flakeModule; };
}
```

______________________________________________________________________

## // modules/eval-nix2llm-module.nix //

```nix
{
  flake-parts-lib,
  lib,
  self,
  inputs,
  ...
}:
let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) mkOption types;
in
{
  options.perSystem = mkPerSystemOption {
    options.evalNix2LlmModule = mkOption {
      description = ''
        Function for evaluating a configured `nix2llm` instance
      '';
      type = types.functionTo types.raw;
    };
  };

  config.perSystem =
    {
      pkgs,
      self',
      inputs',
      ...
    }:
    {
      evalNix2LlmModule =
        name: module:
        lib.evalModules {
          modules = [
            self.modules.nix2llm.default
            module
          ];
          specialArgs = {
            inherit
              pkgs
              self'
              inputs
              inputs'
              name
              ;
          };
          class = "nix2llm";
        };
    };
}
```

______________________________________________________________________

## // modules/mk-nix2llm-container.nix //

```nix
{ lib, flake-parts-lib, ... }:
let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) types mkOption;
in
{
  options.perSystem = mkPerSystemOption {
    options.mkNix2LlmContainer = mkOption {
      description = ''
        Build a `nix2llm` container
      '';
      type = types.functionTo types.raw;
    };
  };

  config.perSystem =
    { config, inputs', ... }:
    {
      mkNix2LlmContainer =
        name: module:
        let
          nimi = inputs'.nimi.packages.default;

          nix2llmCfg = (config.evalNix2LlmModule name module).config;

          image = nimi.mkContainerImage {
            inherit (nix2llmCfg) services meta;
            imports = [
              (lib.mkAliasOptionModule [ "container" ] [ "settings" "container" ])
              (lib.mkAliasOptionModule [ "startup" ] [ "settings" "startup" ])
              (lib.mkAliasOptionModule [ "logging" ] [ "settings" "logging" ])
              (lib.mkAliasOptionModule [ "restart" ] [ "settings" "restart" ])
              nix2llmCfg.nimiSettings
            ];
          };
        in
        image.overrideAttrs (old: {
          passthru = (old.passthru or { }) // nix2llmCfg.passthru;
        });
    };
}
```

______________________________________________________________________

## // modules/nix2llm-module.nix //

```nix
{ inputs, ... }:
{
  flake.modules.nix2llm.default = inputs.import-tree ../nix2llm;
}
```

______________________________________________________________________

## // nix2llm/gateway/config.nix //

this is the core configuration module unique to `nix2llm`:

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkIf
    mkEnableOption
    literalExpression
    types
    ;

  cfg = config.gateway;

  gatewayConfigType = types.submodule {
    options = {
      enable = mkEnableOption "the nix2llm gateway service";

      port = mkOption {
        description = ''
          The TCP port the gateway listens on.
        '';
        type = types.port;
        default = 4000;
        example = 8080;
      };

      host = mkOption {
        description = ''
          The IP address the gateway binds to.

          Use "0.0.0.0" to listen on all interfaces (required for
          container networking). Use "127.0.0.1" for local-only access.
        '';
        type = types.str;
        default = "0.0.0.0";
      };

      workers = mkOption {
        description = ''
          Number of uvicorn worker processes.

          Set to 1 for most use cases. Increase only if you are
          cpu-bound on request transformation (unlikely for a proxy).
        '';
        type = types.ints.positive;
        default = 1;
      };

      logLevel = mkOption {
        description = ''
          Logging level for the gateway process.

          One of: debug, info, warning, error, critical.
        '';
        type = types.enum [ "debug" "info" "warning" "error" "critical" ];
        default = "info";
      };

      cgp = mkOption {
        description = ''
          Cloud GPU Provider (CGP) backend configuration.

          This is the **primary** backend. Every request is routed here
          first. If the cgp is not configured, unreachable, or returns
          a 5xx error, the request falls through to openrouter.

          Set `cgp.apiBase` to the base url of any openai-compatible
          inference server: vllm, tgi, sglang, ollama, etc.

          The `cgp.apiKey` is optional — many local inference servers
          don't require authentication.
        '';
        type = types.submodule {
          options = {
            apiBase = mkOption {
              description = ''
                Base URL of the CGP inference endpoint.

                Must be a full URL including scheme and port.
                Do NOT include `/v1` suffix — the gateway appends it.

                Set to empty string to disable CGP routing entirely
                (all requests go directly to openrouter).
              '';
              type = types.str;
              default = "";
              example = "http://10.0.0.50:8000";
            };

            apiKey = mkOption {
              description = ''
                API key for the CGP endpoint.

                Optional. Many local inference servers (vllm, ollama)
                don't require authentication. If your server does,
                provide the key here or via the `CGP_API_KEY`
                environment variable at runtime.

                IMPORTANT: prefer runtime injection via env var or
                secret file over baking keys into the nix store.
              '';
              type = types.str;
              default = "";
            };

            apiKeyFile = mkOption {
              description = ''
                Path to a file containing the CGP API key.

                Read at container startup. Takes precedence over
                `cgp.apiKey` and the `CGP_API_KEY` env var.

                Use this for secrets management (e.g. mounted from
                `/run/secrets/`).
              '';
              type = types.str;
              default = "";
              example = "/run/secrets/cgp-api-key";
            };

            timeout = mkOption {
              description = ''
                Timeout in seconds for CGP requests.

                If the CGP does not respond within this window, the
                request is considered failed and falls through to
                openrouter. For inference workloads, keep this generous.
              '';
              type = types.ints.positive;
              default = 120;
            };

            connectTimeout = mkOption {
              description = ''
                Connection timeout in seconds for CGP.

                How long to wait for the TCP connection to establish.
                This should be short — if you can't connect in 5s, the
                server is probably down and we should fall through fast.
              '';
              type = types.ints.positive;
              default = 5;
            };

            healthEndpoint = mkOption {
              description = ''
                Health check endpoint on the CGP server.

                Used by the gateway's readiness probe to verify the
                CGP is alive before routing traffic. Relative to apiBase.
              '';
              type = types.str;
              default = "/health";
            };

            models = mkOption {
              description = ''
                Explicit model name mapping for the CGP backend.

                Keys are the model names clients send in requests.
                Values are the model names the CGP backend expects.

                If empty, model names are passed through unchanged.

                Example: map "gpt-4o" requests to a local model name
                so callers don't need to know the backend model id.
              '';
              type = types.attrsOf types.str;
              default = { };
              example = {
                "gpt-4o" = "meta-llama/Llama-3.3-70B-Instruct";
                "gpt-4o-mini" = "meta-llama/Llama-3.1-8B-Instruct";
              };
            };
          };
        };
        default = { };
      };

      openrouter = mkOption {
        description = ''
          OpenRouter fallback backend configuration.

          This is the **fallback** backend. Requests only reach
          openrouter when:
          - CGP is not configured (`cgp.apiBase` is empty)
          - CGP is unreachable (connection refused/timeout)
          - CGP returns a 5xx server error

          Requests that fail at the CGP with 4xx errors are
          NOT retried at openrouter — 4xx means the request
          itself is bad, not the server.
        '';
        type = types.submodule {
          options = {
            apiBase = mkOption {
              description = ''
                Base URL of the OpenRouter API.

                You should not need to change this unless you are
                using a custom openrouter-compatible gateway.
              '';
              type = types.str;
              default = "https://openrouter.ai/api";
            };

            apiKey = mkOption {
              description = ''
                OpenRouter API key.

                IMPORTANT: prefer runtime injection via env var
                `OPENROUTER_API_KEY` or secret file over baking
                keys into the nix store.
              '';
              type = types.str;
              default = "";
            };

            apiKeyFile = mkOption {
              description = ''
                Path to a file containing the OpenRouter API key.

                Read at container startup. Takes precedence over
                `openrouter.apiKey` and the `OPENROUTER_API_KEY`
                env var.
              '';
              type = types.str;
              default = "";
              example = "/run/secrets/openrouter-api-key";
            };

            timeout = mkOption {
              description = ''
                Timeout in seconds for OpenRouter requests.
              '';
              type = types.ints.positive;
              default = 120;
            };

            defaultModel = mkOption {
              description = ''
                Default model to use on openrouter when the client's
                requested model is not found in the cgp model map.

                If empty, the client's model name is passed through
                unchanged to openrouter.
              '';
              type = types.str;
              default = "";
              example = "anthropic/claude-sonnet-4-20250514";
            };

            models = mkOption {
              description = ''
                Model name mapping for the openrouter backend.

                Keys are client-facing model names. Values are
                openrouter model identifiers.

                If a model is in BOTH cgp.models and openrouter.models,
                the cgp mapping is tried first, and this mapping is
                used on fallback.
              '';
              type = types.attrsOf types.str;
              default = { };
              example = {
                "gpt-4o" = "openai/gpt-4o";
                "claude-sonnet" = "anthropic/claude-sonnet-4-20250514";
              };
            };

            siteUrl = mkOption {
              description = ''
                Value for the HTTP-Referer header sent to openrouter.

                Used for app attribution on openrouter leaderboards.
              '';
              type = types.str;
              default = "";
            };

            siteName = mkOption {
              description = ''
                Value for the X-Title header sent to openrouter.

                Used for app attribution on openrouter leaderboards.
              '';
              type = types.str;
              default = "nix2llm";
            };
          };
        };
        default = { };
      };
    };
  };
in
{
  _class = "nix2llm";

  options.gateway = mkOption {
    description = ''
      The nix2llm gateway configuration.

      Configure the cgp-first routing behavior, backend endpoints,
      and runtime parameters for the openai-compatible gateway.
    '';
    example = literalExpression ''
      gateway = {
        enable = true;
        port = 4000;
        cgp.apiBase = "http://10.0.0.50:8000";
        openrouter.apiKeyFile = "/run/secrets/openrouter-api-key";
      };
    '';
    type = gatewayConfigType;
    default = { };
  };

  config = mkIf cfg.enable {
    exposedPorts = {
      "${toString cfg.port}/tcp" = { };
    };

    extraEnv = {
      NIX2LLM_HOST = cfg.host;
      NIX2LLM_PORT = toString cfg.port;
      NIX2LLM_WORKERS = toString cfg.workers;
      NIX2LLM_LOG_LEVEL = cfg.logLevel;
      NIX2LLM_CGP_API_BASE = cfg.cgp.apiBase;
      NIX2LLM_CGP_TIMEOUT = toString cfg.cgp.timeout;
      NIX2LLM_CGP_CONNECT_TIMEOUT = toString cfg.cgp.connectTimeout;
      NIX2LLM_CGP_HEALTH_ENDPOINT = cfg.cgp.healthEndpoint;
      NIX2LLM_OPENROUTER_API_BASE = cfg.openrouter.apiBase;
      NIX2LLM_OPENROUTER_TIMEOUT = toString cfg.openrouter.timeout;
      NIX2LLM_OPENROUTER_SITE_URL = cfg.openrouter.siteUrl;
      NIX2LLM_OPENROUTER_SITE_NAME = cfg.openrouter.siteName;
    };
  };
}
```

______________________________________________________________________

## // nix2llm/gateway/service.nix //

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;

  cfg = config.gateway;

  nix2llmPackage = pkgs.callPackage ../../gateway/package.nix { };

  # // secrets // read api keys from files at startup
  secretLoader = pkgs.writeShellApplication {
    name = "nix2llm-load-secrets";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # // cgp // api key
      if [[ -n "''${NIX2LLM_CGP_API_KEY_FILE:-}" ]] && [[ -f "$NIX2LLM_CGP_API_KEY_FILE" ]]; then
        export CGP_API_KEY
        CGP_API_KEY="$(cat "$NIX2LLM_CGP_API_KEY_FILE")"
      fi

      # // openrouter // api key
      if [[ -n "''${NIX2LLM_OPENROUTER_API_KEY_FILE:-}" ]] && [[ -f "$NIX2LLM_OPENROUTER_API_KEY_FILE" ]]; then
        export OPENROUTER_API_KEY
        OPENROUTER_API_KEY="$(cat "$NIX2LLM_OPENROUTER_API_KEY_FILE")"
      fi

      exec "$@"
    '';
  };

  wrapper = pkgs.writeShellApplication {
    name = "nix2llm-gateway";
    runtimeInputs = [ nix2llmPackage secretLoader ];
    text = ''
      nix2llm-load-secrets \
        python -m nix2llm \
          --host "''${NIX2LLM_HOST:-0.0.0.0}" \
          --port "''${NIX2LLM_PORT:-4000}" \
          --workers "''${NIX2LLM_WORKERS:-1}" \
          --log-level "''${NIX2LLM_LOG_LEVEL:-info}"
    '';
  };
in
{
  _class = "nix2llm";

  config = mkIf cfg.enable {
    systemPackages = [ nix2llmPackage ];

    services.nix2llm-gateway = {
      process.argv = [ (lib.getExe wrapper) ];
    };
  };
}
```

______________________________________________________________________

## // nix2llm/gateway/health.nix //

```nix
{ config, lib, ... }:
let
  inherit (lib) mkIf;

  cfg = config.gateway;
in
{
  _class = "nix2llm";

  config = mkIf cfg.enable {
    nimiSettings.container.imageConfig.Healthcheck = {
      Test = [
        "CMD"
        "curl"
        "-f"
        "http://localhost:${toString cfg.port}/health"
      ];
      Interval = 30000000000;   # 30s in nanoseconds
      Timeout = 5000000000;     # 5s
      Retries = 3;
    };
  };
}
```

______________________________________________________________________

## // services/nix2llm-gateway.nix //

the nimi modular service definition (separate from the nix2llm module tree):

```nix
{ pkgs, ... }:
{ lib, config, ... }:
let
  inherit (lib) mkOption mkPackageOption types;

  cfg = config.nix2llmGateway;

  nix2llmPackage = cfg.package;

  wrapper = pkgs.writeShellApplication {
    name = "nix2llm-gateway";
    runtimeEnv = cfg.environmentVariables;
    text = ''
      ${lib.getExe nix2llmPackage} \
        --host ${cfg.host} \
        --port ${toString cfg.port} \
        --workers ${toString cfg.workers} \
        --log-level ${cfg.logLevel} \
        "$@"
    '';
  };
in
{
  _class = "service";

  options.nix2llmGateway = {
    package = mkPackageOption pkgs "nix2llm" { };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = ''
        The IP address to bind to.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 4000;
      description = ''
        The TCP port to listen on.
      '';
    };

    workers = mkOption {
      type = types.ints.positive;
      default = 1;
      description = ''
        Number of uvicorn workers.
      '';
    };

    logLevel = mkOption {
      type = types.enum [ "debug" "info" "warning" "error" "critical" ];
      default = "info";
      description = ''
        Logging verbosity.
      '';
    };

    environmentVariables = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Extra environment variables for the gateway process.
      '';
      example = {
        CGP_API_KEY = "sk-local-1234";
        OPENROUTER_API_KEY = "sk-or-v1-xxxx";
      };
    };
  };

  config.process.argv = [ (lib.getExe wrapper) ];
}
```

______________________________________________________________________

## // python source: gateway/pyproject.toml //

```toml
[project]
name = "nix2llm"
version = "0.1.0"
description = "cgp-first openai gateway for nix2gpu"
requires-python = ">=3.12"
license = "MIT"
dependencies = [
    "starlette>=0.45.0",
    "uvicorn[standard]>=0.34.0",
    "httpx>=0.28.0",
    "pydantic>=2.10.0",
    "pydantic-settings>=2.7.0",
    "sse-starlette>=2.2.0",
]

[project.scripts]
nix2llm = "nix2llm.__main__:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.ruff]
target-version = "py312"
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "I", "N", "W", "UP", "B", "A", "SIM", "TCH"]
```

______________________________________________________________________

## // python source: gateway/src/nix2llm/config.py //

```python
"""
nix2llm gateway configuration.

all config is read from environment variables with the NIX2LLM_ prefix.
pydantic-settings handles parsing, validation, and defaults.

env vars:
    NIX2LLM_HOST              - bind address (default: 0.0.0.0)
    NIX2LLM_PORT              - bind port (default: 4000)
    NIX2LLM_WORKERS           - uvicorn workers (default: 1)
    NIX2LLM_LOG_LEVEL         - log level (default: info)
    NIX2LLM_CGP_API_BASE      - cgp endpoint base url (default: "" = disabled)
    NIX2LLM_CGP_API_KEY_FILE  - path to cgp api key file
    CGP_API_KEY               - cgp api key (direct)
    NIX2LLM_CGP_TIMEOUT       - cgp request timeout seconds (default: 120)
    NIX2LLM_CGP_CONNECT_TIMEOUT - cgp connect timeout seconds (default: 5)
    NIX2LLM_CGP_HEALTH_ENDPOINT - cgp health check path (default: /health)
    NIX2LLM_CGP_MODELS_JSON   - json string of cgp model name mappings
    NIX2LLM_OPENROUTER_API_BASE     - openrouter base url
    OPENROUTER_API_KEY              - openrouter api key (direct)
    NIX2LLM_OPENROUTER_API_KEY_FILE - path to openrouter api key file
    NIX2LLM_OPENROUTER_TIMEOUT      - openrouter timeout seconds (default: 120)
    NIX2LLM_OPENROUTER_DEFAULT_MODEL - default openrouter model
    NIX2LLM_OPENROUTER_MODELS_JSON   - json string of openrouter model mappings
    NIX2LLM_OPENROUTER_SITE_URL      - HTTP-Referer header for openrouter
    NIX2LLM_OPENROUTER_SITE_NAME     - X-Title header for openrouter
"""

from __future__ import annotations

import json
from pathlib import Path

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings


class CgpConfig(BaseSettings):
    """cloud gpu provider backend configuration."""

    model_config = {"env_prefix": "NIX2LLM_CGP_", "extra": "ignore"}

    api_base: str = ""
    api_key: str = ""                  # also reads CGP_API_KEY (no prefix)
    api_key_file: str = ""
    timeout: int = 120
    connect_timeout: int = 5
    health_endpoint: str = "/health"
    models_json: str = "{}"

    @model_validator(mode="after")
    def _load_key_file(self) -> "CgpConfig":
        if self.api_key_file and Path(self.api_key_file).is_file():
            self.api_key = Path(self.api_key_file).read_text().strip()
        return self

    @property
    def enabled(self) -> bool:
        return bool(self.api_base)

    @property
    def models(self) -> dict[str, str]:
        return json.loads(self.models_json)


class OpenRouterConfig(BaseSettings):
    """openrouter fallback backend configuration."""

    model_config = {"env_prefix": "NIX2LLM_OPENROUTER_", "extra": "ignore"}

    api_base: str = "https://openrouter.ai/api"
    api_key: str = ""                  # also reads OPENROUTER_API_KEY (no prefix)
    api_key_file: str = ""
    timeout: int = 120
    default_model: str = ""
    models_json: str = "{}"
    site_url: str = ""
    site_name: str = "nix2llm"

    @model_validator(mode="after")
    def _load_key_file(self) -> "OpenRouterConfig":
        if self.api_key_file and Path(self.api_key_file).is_file():
            self.api_key = Path(self.api_key_file).read_text().strip()
        return self

    @property
    def models(self) -> dict[str, str]:
        return json.loads(self.models_json)


class GatewayConfig(BaseSettings):
    """top-level gateway configuration."""

    model_config = {"env_prefix": "NIX2LLM_", "extra": "ignore"}

    host: str = "0.0.0.0"
    port: int = 4000
    workers: int = 1
    log_level: str = "info"

    cgp: CgpConfig = CgpConfig()
    openrouter: OpenRouterConfig = OpenRouterConfig()

    @field_validator("log_level")
    @classmethod
    def _validate_log_level(cls, v: str) -> str:
        allowed = {"debug", "info", "warning", "error", "critical"}
        if v.lower() not in allowed:
            raise ValueError(f"log_level must be one of {allowed}")
        return v.lower()
```

______________________________________________________________________

## // python source: gateway/src/nix2llm/types.py //

pydantic models that mirror the openai api request/response schemas.
these are the **only** types used throughout the codebase.

```python
"""
openai-compatible request/response types.

these models define the exact wire format. no extras, no extensions.
callers send these, backends receive these, responses match these.
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


# ── requests ──────────────────────────────────────────────────────

class ChatMessage(BaseModel):
    role: Literal["system", "user", "assistant", "tool"]
    content: str | list[Any] | None = None
    name: str | None = None
    tool_calls: list[Any] | None = None
    tool_call_id: str | None = None


class ChatCompletionRequest(BaseModel):
    model: str
    messages: list[ChatMessage]
    temperature: float | None = None
    top_p: float | None = None
    n: int | None = None
    stream: bool = False
    stop: str | list[str] | None = None
    max_tokens: int | None = None
    presence_penalty: float | None = None
    frequency_penalty: float | None = None
    logit_bias: dict[str, float] | None = None
    user: str | None = None
    tools: list[Any] | None = None
    tool_choice: Any | None = None
    response_format: Any | None = None
    seed: int | None = None


class CompletionRequest(BaseModel):
    model: str
    prompt: str | list[str]
    max_tokens: int | None = None
    temperature: float | None = None
    top_p: float | None = None
    n: int | None = None
    stream: bool = False
    stop: str | list[str] | None = None
    presence_penalty: float | None = None
    frequency_penalty: float | None = None
    logit_bias: dict[str, float] | None = None
    user: str | None = None
    seed: int | None = None


class EmbeddingRequest(BaseModel):
    model: str
    input: str | list[str]
    encoding_format: str | None = None
    user: str | None = None


# ── responses ─────────────────────────────────────────────────────

class Usage(BaseModel):
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0


class ChatCompletionChoice(BaseModel):
    index: int = 0
    message: ChatMessage
    finish_reason: str | None = None


class ChatCompletionResponse(BaseModel):
    id: str
    object: str = "chat.completion"
    created: int
    model: str
    choices: list[ChatCompletionChoice]
    usage: Usage | None = None


class ErrorDetail(BaseModel):
    message: str
    type: str
    param: str | None = None
    code: str | None = None


class ErrorResponse(BaseModel):
    error: ErrorDetail
```

______________________________________________________________________

## // python source: gateway/src/nix2llm/providers/base.py //

```python
"""
abstract provider interface.

every backend (cgp, openrouter) implements this protocol.
the router calls these methods — it never touches httpx directly.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from typing import Any

import httpx


class ProviderError(Exception):
    """raised when a provider request fails."""

    def __init__(
        self,
        message: str,
        status_code: int = 500,
        retryable: bool = False,
    ):
        super().__init__(message)
        self.status_code = status_code
        self.retryable = retryable


class Provider(ABC):
    """abstract llm provider backend."""

    @property
    @abstractmethod
    def name(self) -> str:
        """human-readable provider name for logging."""
        ...

    @abstractmethod
    async def request(
        self,
        method: str,
        path: str,
        body: dict[str, Any],
        headers: dict[str, str],
    ) -> httpx.Response:
        """
        send a non-streaming request to the backend.

        args:
            method: http method (POST)
            path: api path (e.g. /v1/chat/completions)
            body: request body dict
            headers: request headers

        returns:
            httpx.Response with the backend's response

        raises:
            ProviderError on failure
        """
        ...

    @abstractmethod
    async def stream(
        self,
        method: str,
        path: str,
        body: dict[str, Any],
        headers: dict[str, str],
    ) -> AsyncIterator[bytes]:
        """
        send a streaming request and yield sse chunks.

        args:
            method: http method (POST)
            path: api path (e.g. /v1/chat/completions)
            body: request body dict
            headers: request headers

        yields:
            raw sse bytes (b"data: {...}\\n\\n")

        raises:
            ProviderError on failure
        """
        ...

    @abstractmethod
    async def health(self) -> bool:
        """check if the backend is reachable and healthy."""
        ...

    @abstractmethod
    def map_model(self, model: str) -> str:
        """
        translate a client model name to a backend model name.

        returns the input unchanged if no mapping exists.
        """
        ...

    async def close(self) -> None:
        """cleanup resources (httpx client, etc)."""
        ...
```

______________________________________________________________________

## // python source: gateway/src/nix2llm/providers/cgp.py //

```python
"""
cloud gpu provider backend.

forwards requests to a local/remote openai-compatible inference server.
this is the PRIMARY backend — all requests try here first.

supports: vllm, tgi, sglang, ollama, any openai-compatible server.
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from typing import Any

import httpx

from nix2llm.config import CgpConfig
from nix2llm.providers.base import Provider, ProviderError

logger = logging.getLogger(__name__)


class CgpProvider(Provider):
    """cloud gpu provider backend."""

    def __init__(self, config: CgpConfig) -> None:
        self._config = config
        self._client = httpx.AsyncClient(
            base_url=config.api_base,
            timeout=httpx.Timeout(
                timeout=config.timeout,
                connect=config.connect_timeout,
            ),
            limits=httpx.Limits(
                max_keepalive_connections=20,
                max_connections=100,
            ),
        )

    @property
    def name(self) -> str:
        return f"cgp({self._config.api_base})"

    def map_model(self, model: str) -> str:
        return self._config.models.get(model, model)

    async def request(
        self,
        method: str,
        path: str,
        body: dict[str, Any],
        headers: dict[str, str],
    ) -> httpx.Response:
        req_headers = {k: v for k, v in headers.items() if k.lower() != "host"}
        if self._config.api_key:
            req_headers["Authorization"] = f"Bearer {self._config.api_key}"

        try:
            response = await self._client.request(
                method=method,
                url=path,
                json=body,
                headers=req_headers,
            )
        except httpx.ConnectError as e:
            raise ProviderError(
                f"cgp connection failed: {e}",
                status_code=503,
                retryable=True,
            ) from e
        except httpx.TimeoutException as e:
            raise ProviderError(
                f"cgp request timed out: {e}",
                status_code=504,
                retryable=True,
            ) from e

        if response.status_code >= 500:
            raise ProviderError(
                f"cgp returned {response.status_code}: {response.text[:200]}",
                status_code=response.status_code,
                retryable=True,
            )

        # 4xx errors are NOT retryable — the request itself is bad
        if response.status_code >= 400:
            raise ProviderError(
                f"cgp returned {response.status_code}: {response.text[:200]}",
                status_code=response.status_code,
                retryable=False,
            )

        return response

    async def stream(
        self,
        method: str,
        path: str,
        body: dict[str, Any],
        headers: dict[str, str],
    ) -> AsyncIterator[bytes]:
        req_headers = {k: v for k, v in headers.items() if k.lower() != "host"}
        if self._config.api_key:
            req_headers["Authorization"] = f"Bearer {self._config.api_key}"

        try:
            async with self._client.stream(
                method=method,
                url=path,
                json=body,
                headers=req_headers,
            ) as response:
                if response.status_code >= 500:
                    body_text = await response.aread()
                    raise ProviderError(
                        f"cgp stream returned {response.status_code}: {body_text[:200]}",
                        status_code=response.status_code,
                        retryable=True,
                    )
                if response.status_code >= 400:
                    body_text = await response.aread()
                    raise ProviderError(
                        f"cgp stream returned {response.status_code}: {body_text[:200]}",
                        status_code=response.status_code,
                        retryable=False,
                    )
                async for chunk in response.aiter_bytes():
                    yield chunk
        except httpx.ConnectError as e:
            raise ProviderError(
                f"cgp stream connection failed: {e}",
                status_code=503,
                retryable=True,
            ) from e
        except httpx.TimeoutException as e:
            raise ProviderError(
                f"cgp stream timed out: {e}",
                status_code=504,
                retryable=True,
            ) from e

    async def health(self) -> bool:
        try:
            response = await self._client.get(
                self._config.health_endpoint,
                timeout=5.0,
            )
            return response.status_code < 400
        except (httpx.ConnectError, httpx.TimeoutException):
            return False

    async def close(self) -> None:
        await self._client.aclose()
```

______________________________________________________________________

## // python source: gateway/src/nix2llm/providers/openrouter.py //

```python
"""
openrouter fallback backend.

only receives requests when cgp is unavailable or returns 5xx.
adds openrouter-specific headers (HTTP-Referer, X-Title) for
app attribution.
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from typing import Any

import httpx

from nix2llm.config import OpenRouterConfig
from nix2llm.providers.base import Provider, ProviderError

logger = logging.getLogger(__name__)


class OpenRouterProvider(Provider):
    """openrouter fallback backend."""

    def __init__(self, config: OpenRouterConfig) -> None:
        self._config = config
        self._client = httpx.AsyncClient(
            base_url=config.api_base,
            timeout=httpx.Timeout(timeout=config.timeout),
            limits=httpx.Limits(
                max_keepalive_connections=20,
                max_connections=100,
            ),
        )

    @property
    def name(self) -> str:
        return "openrouter"

    def map_model(self, model: str) -> str:
        mapped = self._config.models.get(model, "")
        if mapped:
            return mapped
        if self._config.default_model:
            return self._config.default_model
        return model

    def _build_headers(self, headers: dict[str, str]) -> dict[str, str]:
        out = {k: v for k, v in headers.items() if k.lower() != "host"}
        if self._config.api_key:
            out["Authorization"] = f"Bearer {self._config.api_key}"
        if self._config.site_url:
            out["HTTP-Referer"] = self._config.site_url
        if self._config.site_name:
            out["X-Title"] = self._config.site_name
        return out

    async def request(
        self,
        method: str,
        path: str,
        body: dict[str, Any],
        headers: dict[str, str],
    ) -> httpx.Response:
        req_headers = self._build_headers(headers)

        try:
            response = await self._client.request(
                method=method,
                url=path,
                json=body,
                headers=req_headers,
            )
        except (httpx.ConnectError, httpx.TimeoutException) as e:
            raise ProviderError(
                f"openrouter request failed: {e}",
                status_code=502,
                retryable=False,  # nowhere else to fall back to
            ) from e

        if response.status_code >= 400:
            raise ProviderError(
                f"openrouter returned {response.status_code}: {response.text[:200]}",
                status_code=response.status_code,
                retryable=False,
            )

        return response

    async def stream(
        self,
        method: str,
        path: str,
        body: dict[str, Any],
        headers: dict[str, str],
    ) -> AsyncIterator[bytes]:
        req_headers = self._build_headers(headers)

        try:
            async with self._client.stream(
                method=method,
                url=path,
                json=body,
                headers=req_headers,
            ) as response:
                if response.status_code >= 400:
                    body_text = await response.aread()
                    raise ProviderError(
                        f"openrouter stream returned {response.status_code}: {body_text[:200]}",
                        status_code=response.status_code,
                        retryable=False,
                    )
                async for chunk in response.aiter_bytes():
                    yield chunk
        except (httpx.ConnectError, httpx.TimeoutException) as e:
            raise ProviderError(
                f"openrouter stream failed: {e}",
                status_code=502,
                retryable=False,
            ) from e

    async def health(self) -> bool:
        try:
            response = await self._client.get("/v1/models", timeout=5.0)
            return response.status_code < 400
        except (httpx.ConnectError, httpx.TimeoutException):
            return False

    async def close(self) -> None:
        await self._client.aclose()
```

______________________________________________________________________

## // python source: gateway/src/nix2llm/router.py //

```python
"""
cgp-first routing logic.

this is the brain of nix2llm. the algorithm:

1. if cgp is configured, try cgp first
2. if cgp fails with a RETRYABLE error (5xx, timeout, connection refused),
   fall through to openrouter
3. if cgp fails with a NON-RETRYABLE error (4xx), return the error
   immediately — the request itself is bad
4. if cgp is not configured, go directly to openrouter
5. if openrouter fails, return the error — nowhere left to try
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from typing import Any

import httpx

from nix2llm.config import GatewayConfig
from nix2llm.providers.base import Provider, ProviderError
from nix2llm.providers.cgp import CgpProvider
from nix2llm.providers.openrouter import OpenRouterProvider

logger = logging.getLogger(__name__)


class Router:
    """cgp-first request router."""

    def __init__(self, config: GatewayConfig) -> None:
        self._config = config
        self._cgp: CgpProvider | None = None
        self._openrouter: OpenRouterProvider | None = None

        if config.cgp.enabled:
            self._cgp = CgpProvider(config.cgp)
            logger.info("cgp backend enabled: %s", config.cgp.api_base)

        if config.openrouter.api_key:
            self._openrouter = OpenRouterProvider(config.openrouter)
            logger.info("openrouter fallback enabled")

        if not self._cgp and not self._openrouter:
            logger.warning(
                "no backends configured — all requests will fail. "
                "set CGP_API_BASE and/or OPENROUTER_API_KEY."
            )

    async def route_request(
        self,
        method: str,
        path: str,
        body: dict[str, Any],
        headers: dict[str, str],
    ) -> httpx.Response:
        """route a non-streaming request through the provider chain."""
        model = body.get("model", "")

        # // cgp // try primary backend first
        if self._cgp:
            cgp_body = {**body, "model": self._cgp.map_model(model)}
            try:
                logger.debug("routing to cgp: model=%s", cgp_body["model"])
                response = await self._cgp.request(method, path, cgp_body, headers)
                logger.info("cgp served request: model=%s status=%d", model, response.status_code)
                return response
            except ProviderError as e:
                if not e.retryable:
                    logger.warning("cgp non-retryable error: %s", e)
                    raise
                logger.warning("cgp failed (retryable), falling back: %s", e)

        # // openrouter // fallback
        if self._openrouter:
            or_body = {**body, "model": self._openrouter.map_model(model)}
            try:
                logger.debug("routing to openrouter: model=%s", or_body["model"])
                response = await self._openrouter.request(method, path, or_body, headers)
                logger.info(
                    "openrouter served request: model=%s status=%d",
                    model,
                    response.status_code,
                )
                return response
            except ProviderError:
                raise

        raise ProviderError("no backends available", status_code=503, retryable=False)

    async def route_stream(
        self,
        method: str,
        path: str,
        body: dict[str, Any],
        headers: dict[str, str],
    ) -> AsyncIterator[bytes]:
        """route a streaming request through the provider chain."""
        model = body.get("model", "")

        # // cgp // try primary backend first
        if self._cgp:
            cgp_body = {**body, "model": self._cgp.map_model(model)}
            try:
                logger.debug("streaming via cgp: model=%s", cgp_body["model"])
                async for chunk in self._cgp.stream(method, path, cgp_body, headers):
                    yield chunk
                logger.info("cgp served stream: model=%s", model)
                return
            except ProviderError as e:
                if not e.retryable:
                    raise
                logger.warning("cgp stream failed (retryable), falling back: %s", e)

        # // openrouter // fallback
        if self._openrouter:
            or_body = {**body, "model": self._openrouter.map_model(model)}
            try:
                logger.debug("streaming via openrouter: model=%s", or_body["model"])
                async for chunk in self._openrouter.stream(method, path, or_body, headers):
                    yield chunk
                logger.info("openrouter served stream: model=%s", model)
                return
            except ProviderError:
                raise

        raise ProviderError("no backends available", status_code=503, retryable=False)

    async def health(self) -> dict[str, Any]:
        """check health of all configured backends."""
        result: dict[str, Any] = {"status": "ok"}

        if self._cgp:
            result["cgp"] = {
                "configured": True,
                "healthy": await self._cgp.health(),
                "api_base": self._config.cgp.api_base,
            }
        else:
            result["cgp"] = {"configured": False}

        if self._openrouter:
            result["openrouter"] = {
                "configured": True,
                "healthy": await self._openrouter.health(),
            }
        else:
            result["openrouter"] = {"configured": False}

        if not self._cgp and not self._openrouter:
            result["status"] = "degraded"

        return result

    async def close(self) -> None:
        if self._cgp:
            await self._cgp.close()
        if self._openrouter:
            await self._openrouter.close()
```

______________________________________________________________________

## // python source: gateway/src/nix2llm/app.py //

```python
"""
starlette application.

mounts all endpoints and middleware. creates the router on startup.
"""

from __future__ import annotations

import json
import logging
from contextlib import asynccontextmanager
from typing import Any

from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.requests import Request
from starlette.responses import JSONResponse, StreamingResponse
from starlette.routing import Route

from nix2llm.config import GatewayConfig
from nix2llm.providers.base import ProviderError
from nix2llm.router import Router

logger = logging.getLogger(__name__)


router: Router | None = None


@asynccontextmanager
async def lifespan(app: Starlette):
    global router
    config = GatewayConfig()
    router = Router(config)
    logger.info("nix2llm gateway started on %s:%d", config.host, config.port)
    yield
    await router.close()
    logger.info("nix2llm gateway stopped")


async def proxy_endpoint(request: Request) -> JSONResponse | StreamingResponse:
    """generic proxy handler for all /v1/* endpoints."""
    assert router is not None

    body_bytes = await request.body()
    body: dict[str, Any] = json.loads(body_bytes) if body_bytes else {}

    headers = dict(request.headers)
    path = request.url.path
    method = request.method

    is_streaming = body.get("stream", False)

    try:
        if is_streaming:
            async def stream_generator():
                async for chunk in router.route_stream(method, path, body, headers):
                    yield chunk

            return StreamingResponse(
                stream_generator(),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                    "X-Accel-Buffering": "no",
                },
            )
        else:
            response = await router.route_request(method, path, body, headers)
            return JSONResponse(
                content=response.json(),
                status_code=response.status_code,
            )
    except ProviderError as e:
        return JSONResponse(
            content={
                "error": {
                    "message": str(e),
                    "type": "server_error" if e.status_code >= 500 else "invalid_request_error",
                    "param": None,
                    "code": str(e.status_code),
                }
            },
            status_code=e.status_code,
        )


async def health(request: Request) -> JSONResponse:
    """health check endpoint."""
    assert router is not None
    return JSONResponse(await router.health())


async def ready(request: Request) -> JSONResponse:
    """readiness check — returns 200 only when at least one backend is up."""
    assert router is not None
    status = await router.health()
    cgp_ok = status.get("cgp", {}).get("healthy", False)
    or_ok = status.get("openrouter", {}).get("healthy", False)
    if cgp_ok or or_ok:
        return JSONResponse({"ready": True})
    return JSONResponse({"ready": False}, status_code=503)


async def list_models(request: Request) -> JSONResponse:
    """
    /v1/models endpoint.

    returns a merged list of models available across all backends.
    cgp models are listed first.
    """
    assert router is not None
    # delegate to openrouter's model list for now
    # TODO: merge cgp models into the response
    try:
        response = await router.route_request("GET", "/v1/models", {}, dict(request.headers))
        return JSONResponse(content=response.json(), status_code=response.status_code)
    except ProviderError as e:
        return JSONResponse(
            content={"error": {"message": str(e), "type": "server_error"}},
            status_code=e.status_code,
        )


app = Starlette(
    debug=False,
    lifespan=lifespan,
    routes=[
        # // health //
        Route("/health", health, methods=["GET"]),
        Route("/ready", ready, methods=["GET"]),
        # // openai-compatible endpoints //
        Route("/v1/chat/completions", proxy_endpoint, methods=["POST"]),
        Route("/v1/completions", proxy_endpoint, methods=["POST"]),
        Route("/v1/embeddings", proxy_endpoint, methods=["POST"]),
        Route("/v1/models", list_models, methods=["GET"]),
    ],
)
```

______________________________________________________________________

## // python source: gateway/src/nix2llm/__main__.py //

```python
"""nix2llm gateway entrypoint."""

from __future__ import annotations

import argparse
import logging

import uvicorn


def main() -> None:
    parser = argparse.ArgumentParser(description="nix2llm gateway")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=4000)
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--log-level", default="info")
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper()),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    uvicorn.run(
        "nix2llm.app:app",
        host=args.host,
        port=args.port,
        workers=args.workers,
        log_level=args.log_level,
        access_log=True,
    )


if __name__ == "__main__":
    main()
```

______________________________________________________________________

## // python packaging: gateway/package.nix //

```nix
{
  lib,
  python312,
  python312Packages,
}:
let
  python = python312;
  pythonPackages = python312Packages;
in
pythonPackages.buildPythonApplication {
  pname = "nix2llm";
  version = "0.1.0";
  format = "pyproject";

  src = ./.;

  build-system = with pythonPackages; [ hatchling ];

  dependencies = with pythonPackages; [
    starlette
    uvicorn
    httpx
    pydantic
    pydantic-settings
    sse-starlette
  ];

  meta = with lib; {
    description = "cgp-first openai gateway for nix2gpu";
    homepage = "https://github.com/weyl-ai/nix2llm";
    license = licenses.mit;
    mainProgram = "nix2llm";
  };
}
```

______________________________________________________________________

## // examples //

### examples/basic.nix

```nix
{
  # nix build .#basic
  # runs gateway with openrouter only (no cgp)
  perSystem.nix2llm.basic = {
    gateway = {
      enable = true;
      port = 4000;
    };
  };
}
```

### examples/with-cgp.nix

```nix
{
  # nix build .#with-cgp
  # routes to cgp first, falls back to openrouter
  perSystem =
    { ... }:
    {
      nix2llm."with-cgp" = {
        gateway = {
          enable = true;
          port = 4000;

          cgp = {
            apiBase = "http://10.0.0.50:8000";
            connectTimeout = 3;
            timeout = 180;
            models = {
              "gpt-4o" = "meta-llama/Llama-3.3-70B-Instruct";
              "gpt-4o-mini" = "meta-llama/Llama-3.1-8B-Instruct";
            };
          };

          openrouter = {
            apiKeyFile = "/run/secrets/openrouter-api-key";
            models = {
              "gpt-4o" = "openai/gpt-4o";
              "claude-sonnet" = "anthropic/claude-sonnet-4-20250514";
            };
          };
        };

        exposedPorts = {
          "4000/tcp" = { };
        };
      };
    };
}
```

### examples/with-tailscale.nix

```nix
{
  # nix build .#with-tailscale
  # gateway accessible via tailscale mesh
  perSystem =
    { ... }:
    {
      nix2llm."with-tailscale" = {
        gateway = {
          enable = true;
          port = 4000;
          cgp.apiBase = "http://gpu-node:8000";
          openrouter.apiKeyFile = "/run/secrets/openrouter-api-key";
        };

        tailscale = {
          enable = true;
          authKey = "/run/secrets/tailscale-auth";
        };

        registries = [ "ghcr.io/weyl-ai" ];
      };
    };
}
```

______________________________________________________________________

## // template: templates/basic/flake.nix //

```nix
{
  description = "nix2llm gateway template";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-parts.url = "github:hercules-ci/flake-parts";

    nix2llm = {
      url = "github:weyl-ai/nix2llm";
      inputs.flake-parts.follows = "flake-parts";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, systems, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ ./default.nix ];
      systems = import systems;

      perSystem =
        { system, ... }:
        {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        };
    };
}
```

### templates/basic/default.nix

```nix
{ inputs, ... }:
{
  imports = [ inputs.nix2llm.flakeModule ];

  perSystem.nix2llm.my-gateway = {
    gateway = {
      enable = true;
      port = 4000;
      cgp.apiBase = "http://localhost:8000";
      openrouter.apiKeyFile = "/run/secrets/openrouter-api-key";
    };
    registries = [ "ghcr.io/my-org" ];
  };
}
```

______________________________________________________________________

## // startup-script/startup.sh //

```bash
# shellcheck shell=bash

set -euo pipefail

gum log --level debug "Container initialization starting..."

gum log --level debug "Writing runtime directories"
# // critical // runtime directories
mkdir -p /tmp /var/tmp /run /run/sshd /var/log /var/empty
chmod 1777 /tmp /var/tmp
chmod 755 /run/sshd

gum log --level debug "Setting up environment"
export TMPDIR=/tmp
export NIX_BUILD_TOP=/tmp

gum log --level debug "Enabling userspace networking"
# // devices // userspace networking
mkdir -p /dev/net

if [ -c /dev/net/tun ]; then
  if ! (exec 3<>/dev/net/tun) 2>/dev/null; then
    gum log --level warn "/dev/net/tun exists but cannot be opened"
  fi
else
  gum log --level warn "/dev/net/tun not present"
fi

# // dynamic // shadow file
if [ ! -f /etc/shadow ]; then
  cp /nix/store/*/etc/shadow /etc/shadow
  chmod 0640 /etc/shadow
fi

# // root // password
if [ -n "${ROOT_PASSWORD:-}" ]; then
  gum log --level debug "Setting root password..."
  echo "root:$ROOT_PASSWORD" | chpasswd
else
  gum log --level debug "Enabling passwordless root..."
  passwd -d root
fi

export HOME="/root"

gum log --level debug "Adding SSH keys..."
# // ssh // keys
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [ -n "${SSH_PUBLIC_KEYS:-}" ]; then
  echo "$SSH_PUBLIC_KEYS" >"$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"
fi

for type in rsa ed25519; do
  key="/etc/ssh/ssh_host_${type}_key"
  [ ! -f "$key" ] && ssh-keygen -t "$type" -f "$key" -N "" >/dev/null 2>&1
done

gum log --level debug "Setting XDG dirs"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_DATA_DIRS="/usr/local/share:/usr/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CONFIG_DIRS="/etc/xdg"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_RUNTIME_DIR="/run/user/$UID"
export XDG_BIN_HOME="$HOME/.local/bin"

# // secrets // load api keys from files
if [[ -n "${NIX2LLM_CGP_API_KEY_FILE:-}" ]] && [[ -f "${NIX2LLM_CGP_API_KEY_FILE}" ]]; then
  gum log --level debug "Loading CGP API key from file..."
  export CGP_API_KEY
  CGP_API_KEY="$(cat "$NIX2LLM_CGP_API_KEY_FILE")"
fi

if [[ -n "${NIX2LLM_OPENROUTER_API_KEY_FILE:-}" ]] && [[ -f "${NIX2LLM_OPENROUTER_API_KEY_FILE}" ]]; then
  gum log --level debug "Loading OpenRouter API key from file..."
  export OPENROUTER_API_KEY
  OPENROUTER_API_KEY="$(cat "$NIX2LLM_OPENROUTER_API_KEY_FILE")"
fi

# // config // extra startup script
gum log --level debug "Running extra startup script..."
```

______________________________________________________________________

## // dev environment //

### dev/devshell.nix

```nix
{
  perSystem =
    { pkgs, inputs', ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          docker
          podman
          inputs'.nix2container.packages.skopeo-nix2container
          dive
          gh

          # // python dev //
          python312
          uv
          ruff

          # // testing //
          curl
          jq
          httpie
        ];
      };
    };
}
```

### dev/formatter.nix

```nix
{ inputs, ... }:
let
  indentWidth = 2;
  lineLength = 100;
in
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem.treefmt = {
    projectRootFile = "flake.nix";
    programs = {
      keep-sorted.enable = true;

      nixfmt = {
        enable = true;
        strict = true;
        width = lineLength;
      };

      shfmt = {
        enable = true;
        indent_size = indentWidth;
      };
      shellcheck.enable = true;

      statix.enable = true;
      deadnix.enable = true;

      ruff-check.enable = true;
      ruff-format.enable = true;

      yamlfmt.enable = true;
      mdformat.enable = true;
    };
  };
}
```

______________________________________________________________________

## // testing //

### manual smoke test

```bash
# 1. start the gateway (dev mode)
cd gateway && uv run python -m nix2llm --log-level debug

# 2. test health
curl http://localhost:4000/health | jq .

# 3. test chat completions (non-streaming)
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "hello"}]
  }' | jq .

# 4. test streaming
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "hello"}],
    "stream": true
  }'

# 5. test embeddings
curl http://localhost:4000/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "text-embedding-3-small",
    "input": "hello world"
  }' | jq .

# 6. test models list
curl http://localhost:4000/v1/models | jq .
```

### container test

```bash
# build container
nix build .#basic

# load and run
docker load < result
docker run -p 4000:4000 \
  -e OPENROUTER_API_KEY="sk-or-v1-xxx" \
  -e NIX2LLM_CGP_API_BASE="http://host.docker.internal:8000" \
  basic:latest

# test from host
curl http://localhost:4000/health | jq .
```

______________________________________________________________________

## // environment variables reference //

| variable                          | required | default                        | description                                   |
|-----------------------------------|----------|--------------------------------|-----------------------------------------------|
| `NIX2LLM_HOST`                    | no       | `0.0.0.0`                      | bind address                                  |
| `NIX2LLM_PORT`                    | no       | `4000`                         | bind port                                     |
| `NIX2LLM_WORKERS`                 | no       | `1`                            | uvicorn workers                               |
| `NIX2LLM_LOG_LEVEL`               | no       | `info`                         | debug/info/warning/error/critical             |
| `NIX2LLM_CGP_API_BASE`            | no       | `""` (disabled)                | cgp endpoint base url                         |
| `CGP_API_KEY`                      | no       | `""`                           | cgp api key                                   |
| `NIX2LLM_CGP_API_KEY_FILE`        | no       | `""`                           | path to file containing cgp api key           |
| `NIX2LLM_CGP_TIMEOUT`             | no       | `120`                          | cgp request timeout (seconds)                 |
| `NIX2LLM_CGP_CONNECT_TIMEOUT`     | no       | `5`                            | cgp connection timeout (seconds)              |
| `NIX2LLM_CGP_HEALTH_ENDPOINT`     | no       | `/health`                      | cgp health check path                         |
| `NIX2LLM_CGP_MODELS_JSON`         | no       | `{}`                           | json model name mapping for cgp               |
| `NIX2LLM_OPENROUTER_API_BASE`     | no       | `https://openrouter.ai/api`    | openrouter base url                           |
| `OPENROUTER_API_KEY`               | **yes*** | `""`                           | openrouter api key (* unless cgp-only)        |
| `NIX2LLM_OPENROUTER_API_KEY_FILE` | no       | `""`                           | path to file containing openrouter api key    |
| `NIX2LLM_OPENROUTER_TIMEOUT`      | no       | `120`                          | openrouter request timeout (seconds)          |
| `NIX2LLM_OPENROUTER_DEFAULT_MODEL`| no       | `""`                           | default model for unmapped requests           |
| `NIX2LLM_OPENROUTER_MODELS_JSON`  | no       | `{}`                           | json model name mapping for openrouter        |
| `NIX2LLM_OPENROUTER_SITE_URL`     | no       | `""`                           | HTTP-Referer header for openrouter            |
| `NIX2LLM_OPENROUTER_SITE_NAME`    | no       | `nix2llm`                      | X-Title header for openrouter                 |

______________________________________________________________________

## // key design decisions //

1. **no cuda in the gateway container** — this is a proxy, not an inference server. it doesn't need gpu access. the `nix2gpu` base gives you ssh, tailscale, and home-manager for free. cuda is disabled by default but available via `cuda.enable = true` if you want to colocate.

2. **4xx errors are terminal** — if cgp returns a 400/401/403/404/422, the request is malformed or unauthorized. retrying at openrouter with the same bad request is pointless and wastes money.

3. **streaming is a first-class path** — the sse proxy yields raw bytes, no buffering, no re-parsing. the gateway is transparent — it doesn't decode or transform sse events.

4. **model mapping is explicit** — no magic name resolution. if you want `gpt-4o` to route to `meta-llama/Llama-3.3-70B-Instruct` on your cgp, you say so in the config. unmapped models pass through unchanged.

5. **secrets never enter the nix store** — api keys are injected at runtime via env vars or file mounts. the nix config only stores file paths, never key values.

6. **zero state** — no database, no redis, no disk persistence. every request is independent. restart the container and nothing is lost (because nothing was stored).

______________________________________________________________________

## // what to build first //

priority order for implementation:

1. `gateway/src/nix2llm/` — the python source (config, types, providers, router, app, main)
2. `gateway/pyproject.toml` + `gateway/package.nix` — packaging
3. `nix2llm/gateway/` — the three nix module files (config.nix, service.nix, health.nix)
4. `modules/` — the four flake integration modules
5. `nix2llm/` — remaining nix modules (copy from nix2gpu, remove cuda defaults)
6. `examples/` + `templates/` — usage examples
7. `docs/` — documentation
8. `dev/` + `checks/` — tooling

______________________________________________________________________

## // non-goals (do NOT implement) //

- virtual keys / api key management
- cost tracking / spend limits
- admin dashboard / web ui
- database (postgres, sqlite, redis)
- rate limiting (use nginx/caddy in front if needed)
- authentication (use reverse proxy if needed)
- caching (use varnish/redis in front if needed)
- load balancing across multiple cgp instances (use dns/haproxy)
- provider support beyond cgp + openrouter
- python sdk / client library

______________________________________________________________________

## // code standards //

- **code is truth, types describe** — never delete working code to satisfy type errors. fix the types.
- **no greps, no shortcuts** — read complete files. no `grep -r`, no `find | xargs`, no partial views.
- **read SKILL.md** before modifying any project that has one.
- **ruff** for python linting + formatting (configured in pyproject.toml).
- **nixfmt-strict** for nix formatting.
- **shellcheck + shfmt** for bash.
- **resholve** for all shell scripts in nix derivations.
- **gum** for structured logging in startup scripts.
