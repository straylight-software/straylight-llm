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
    { pkgs, self', ... }:
    let
      # Get the straylight-llm package from our flake's packages output
      straylightPackage = self'.packages.straylight-llm;
    in
    {
      nix2gpu.basic = {
        services.straylight-gateway = {
          imports = [
            (lib.modules.importApply ../services/straylight-gateway.nix { inherit pkgs straylightPackage; })
          ];
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
