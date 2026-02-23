# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // straylight-llm // nixos module
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
#     "The sky above the port was the color of television,
#      tuned to a dead channel."
#
#                                                               — Neuromancer
#
# NixOS module for straylight-llm gateway.
# Usage in your NixOS config:
#
#   imports = [ inputs.straylight-llm.nixosModules.default ];
#
#   services.straylight-llm = {
#     enable = true;
#     port = 8080;
#     openFirewall = true;
#   };
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.straylight-llm;
in
{
  options.services.straylight-llm = {
    enable = lib.mkEnableOption "straylight-llm LLM gateway";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The straylight-llm package to use";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Host to bind to";
    };

    workDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/straylight-llm";
      description = "Working directory for straylight-llm";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "straylight";
      description = "User to run straylight-llm as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "straylight";
      description = "Group to run straylight-llm as";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall for straylight-llm port";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "debug"
        "info"
        "warning"
        "error"
      ];
      default = "info";
      description = "Log level";
    };

    requestTimeout = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = "Request timeout in seconds";
    };

    # Provider API key files (read at runtime, not baked into store)
    veniceApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to Venice API key file";
    };

    vertexApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to Vertex AI service account JSON file";
    };

    basetenApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to Baseten API key file";
    };

    openrouterApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to OpenRouter API key file";
    };

    anthropicApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to Anthropic API key file";
    };

    adminApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to admin API key file";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      home = cfg.workDir;
      createHome = true;
    };

    users.groups.${cfg.group} = { };

    systemd.services.straylight-llm = {
      description = "Straylight LLM Gateway";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        HOME = cfg.workDir;
        PORT = toString cfg.port;
        HOST = cfg.host;
        LOG_LEVEL = cfg.logLevel;
        REQUEST_TIMEOUT = toString cfg.requestTimeout;
      };

      # Load API keys from files at service start
      preStart = ''
        ${lib.optionalString (cfg.veniceApiKeyFile != null) ''
          export VENICE_API_KEY="$(cat ${cfg.veniceApiKeyFile})"
        ''}
        ${lib.optionalString (cfg.vertexApiKeyFile != null) ''
          export GOOGLE_APPLICATION_CREDENTIALS="${cfg.vertexApiKeyFile}"
        ''}
        ${lib.optionalString (cfg.basetenApiKeyFile != null) ''
          export BASETEN_API_KEY="$(cat ${cfg.basetenApiKeyFile})"
        ''}
        ${lib.optionalString (cfg.openrouterApiKeyFile != null) ''
          export OPENROUTER_API_KEY="$(cat ${cfg.openrouterApiKeyFile})"
        ''}
        ${lib.optionalString (cfg.anthropicApiKeyFile != null) ''
          export ANTHROPIC_API_KEY="$(cat ${cfg.anthropicApiKeyFile})"
        ''}
        ${lib.optionalString (cfg.adminApiKeyFile != null) ''
          export ADMIN_API_KEY="$(cat ${cfg.adminApiKeyFile})"
        ''}
      '';

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.workDir;
        ExecStart = "${cfg.package}/bin/straylight-llm";
        Restart = "on-failure";
        RestartSec = 5;

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfg.workDir ];

        # Resource limits for billion-agent scale
        LimitNOFILE = 65536;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
