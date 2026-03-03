# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // straylight-llm // gateway service
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
#     "He closed his eyes. Found the ridged face of the power stud."
#
#                                                               — Neuromancer
#
# Nimi modular service definition for the straylight-llm gateway.
# n.b. curried function pattern: outer receives pkgs, inner receives config
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{ pkgs, straylightPackage, ... }:
{ lib, config, ... }:
let
  inherit (lib)
    mkOption
    mkPackageOption
    mkEnableOption
    types
    literalExpression
    ;

  cfg = config.straylightGateway;

  # Runtime tools needed by weapon-server tool execution
  runtimePkgs = [
    pkgs.ripgrep # rg for grep tool
    pkgs.fd # fd for glob tool
    pkgs.git # git for vcs operations
    pkgs.curl # curl for streaming LLM calls
  ];

  # // secrets // load API keys from files at startup
  secretLoader = pkgs.writeShellApplication {
    name = "straylight-load-secrets";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # // anthropic // api key
      if [[ -n "''${ANTHROPIC_API_KEY_FILE:-}" ]] && [[ -f "$ANTHROPIC_API_KEY_FILE" ]]; then
        export ANTHROPIC_API_KEY
        ANTHROPIC_API_KEY="$(cat "$ANTHROPIC_API_KEY_FILE")"
      fi

      # // openrouter // api key
      if [[ -n "''${OPENROUTER_API_KEY_FILE:-}" ]] && [[ -f "$OPENROUTER_API_KEY_FILE" ]]; then
        export OPENROUTER_API_KEY
        OPENROUTER_API_KEY="$(cat "$OPENROUTER_API_KEY_FILE")"
      fi

      exec "$@"
    '';
  };

  # Gateway wrapper with environment
  wrapper = pkgs.writeShellApplication {
    name = "straylight-gateway";
    runtimeInputs = runtimePkgs ++ [
      straylightPackage
      secretLoader
    ];
    runtimeEnv = {
      # n.b. weapon-server uses katip logging, configured via environment
    }
    // lib.optionalAttrs (cfg.openrouter.apiKeyFile != null) {
      OPENROUTER_API_KEY_FILE = cfg.openrouter.apiKeyFile;
    }
    // lib.optionalAttrs (cfg.anthropic.apiKeyFile != null) {
      ANTHROPIC_API_KEY_FILE = cfg.anthropic.apiKeyFile;
    }
    // cfg.environmentVariables;
    text = ''
      straylight-load-secrets straylight-llm "$@"
    '';
  };
in
{
  _class = "service";

  # ════════════════════════════════════════════════════════════════════════════════
  #                                                            // options
  # ════════════════════════════════════════════════════════════════════════════════

  options.straylightGateway = {
    enable = mkEnableOption "straylight-llm gateway service";

    package = mkOption {
      type = types.package;
      default = straylightPackage;
      defaultText = literalExpression "pkgs.callPackage ../gateway/package.nix { }";
      description = ''
        The straylight-llm package to use.
      '';
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = ''
        The IP address to bind to.

        Use "0.0.0.0" to listen on all interfaces (required for
        container networking). Use "127.0.0.1" for local-only access.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 4096;
      description = ''
        The TCP port to listen on.
        n.b. weapon-server defaults to 4096
      '';
    };

    logLevel = mkOption {
      type = types.enum [
        "debug"
        "info"
        "warning"
        "error"
        "critical"
      ];
      default = "info";
      description = ''
        Logging level for the gateway process.
      '';
    };

    # ──────────────────────────────────────────────────────────────────────────────
    #                                                       // anthropic // config
    # ──────────────────────────────────────────────────────────────────────────────

    anthropic = {
      apiKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/run/secrets/anthropic-api-key";
        description = ''
          Path to a file containing the Anthropic API key.

          Read at container startup. Use this for secrets management
          (e.g. mounted from `/run/secrets/`).
        '';
      };
    };

    # ──────────────────────────────────────────────────────────────────────────────
    #                                                       // openrouter // config
    # ──────────────────────────────────────────────────────────────────────────────

    openrouter = {
      apiKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/run/secrets/openrouter-api-key";
        description = ''
          Path to a file containing the OpenRouter API key.

          Read at container startup. Takes precedence over
          the `OPENROUTER_API_KEY` env var.
        '';
      };
    };

    # ──────────────────────────────────────────────────────────────────────────────
    #                                                            // extra // config
    # ──────────────────────────────────────────────────────────────────────────────

    environmentVariables = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        EXTRA_HEADER = "X-Custom-Header";
      };
      description = ''
        Extra environment variables for the gateway process.

        IMPORTANT: prefer runtime injection via secret files over
        baking keys into the nix store. Never put API keys here.
      '';
    };
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #                                                            // config
  # ════════════════════════════════════════════════════════════════════════════════

  config = lib.mkIf cfg.enable {
    process.argv = [ (lib.getExe wrapper) ];
  };
}
