# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // straylight-llm // production
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
#     "The sky above the port was the color of television,
#      tuned to a dead channel."
#
#                                                               — Neuromancer
#
# Production gateway container — all providers enabled, secrets via files.
#
# Build:
#   nix build .#production
#
# Push to GHCR:
#   nix run .#production.copyToGithub
#
# Run locally:
#   nix run .#production.copyToContainerRuntime
#   docker run -p 8080:8080 \
#     -v /path/to/secrets:/run/secrets:ro \
#     -e OPENROUTER_API_KEY_FILE=/run/secrets/openrouter \
#     -e ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic \
#     ghcr.io/straylight-software/straylight-llm:latest
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
      nix2gpu.production = {
        services.straylight-gateway = {
          imports = [
            (lib.modules.importApply ../services/straylight-gateway.nix { inherit pkgs straylightPackage; })
          ];
          straylightGateway = {
            enable = true;
            port = 8080;
            logLevel = "info";

            # All providers — secrets loaded from files at runtime
            anthropic = {
              apiKeyFile = "/run/secrets/anthropic-api-key";
            };

            openrouter = {
              apiKeyFile = "/run/secrets/openrouter-api-key";
            };

            # Additional env vars can be set here
            environmentVariables = {
              # Venice, Vertex, Baseten keys can be added via env
              # VENICE_API_KEY_FILE = "/run/secrets/venice-api-key";
              # GOOGLE_APPLICATION_CREDENTIALS = "/run/secrets/vertex-credentials.json";
              # BASETEN_API_KEY_FILE = "/run/secrets/baseten-api-key";
            };
          };
        };

        exposedPorts = {
          "22/tcp" = { };
          "8080/tcp" = { };
        };

        # Push to GitHub Container Registry
        # Note: The workflow uses github.repository which resolves to the correct org/repo
        registries = [ "ghcr.io/justinfleek" ];
      };
    };
}
