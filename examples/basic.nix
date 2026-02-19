# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // straylight-llm // example basic
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Minimal gateway container — OpenRouter only, no CGP.
#
# Usage:
#   nix build .#basic
#   docker load < result
#   docker run -p 4096:4096 -e OPENROUTER_API_KEY="$OPENROUTER_API_KEY" basic:latest
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      nix2gpu.basic = {
        services.straylight-gateway = {
          imports = [ (lib.modules.importApply ../services/straylight-gateway.nix { inherit pkgs; }) ];
          straylightGateway = {
            enable = true;
            port = 4096;
            logLevel = "info";
          };
        };

        exposedPorts = {
          "22/tcp" = { };
          "4096/tcp" = { };
        };
      };
    };
}
