# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // straylight-llm // example with-secrets
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Gateway with secret files mounted — for production deployments.
#
# Usage:
#   nix build .#with-cgp
#   docker load < result
#   docker run -p 4096:4096 \
#     -v /run/secrets:/run/secrets:ro \
#     with-cgp:latest
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
      nix2gpu."with-cgp" = {
        services.straylight-gateway = {
          imports = [
            (lib.modules.importApply ../services/straylight-gateway.nix { inherit pkgs straylightPackage; })
          ];
          straylightGateway = {
            enable = true;
            port = 4096;
            logLevel = "info";

            # // anthropic // direct API access
            anthropic = {
              apiKeyFile = "/run/secrets/anthropic-api-key";
            };

            # // openrouter // fallback
            openrouter = {
              apiKeyFile = "/run/secrets/openrouter-api-key";
            };
          };
        };

        exposedPorts = {
          "22/tcp" = { };
          "4096/tcp" = { };
        };

        registries = [ "ghcr.io/weyl-ai" ];
      };
    };
}
