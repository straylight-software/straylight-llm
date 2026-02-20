# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                        // straylight-llm //
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
#     "The sky above the port was the color of television,
#      tuned to a dead channel."
#
#                                                               — Neuromancer
#
# CGP-first OpenAI-compatible LLM gateway with verified types.
# Runs inside nix2gpu containers via nimi.
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{
  description = "straylight-llm - CGP-first OpenAI gateway with verified types";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    systems.url = "github:nix-systems/x86_64-linux";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    # Formatting
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Haskell OpenAPI property testing
    haskemathesis.url = "github:weyl-ai/haskemathesis";

    # Home manager for container config
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Container runtime
    # n.b. using master branch — baileylu/minimize-flake has unused import error
    nimi = {
      url = "github:weyl-ai/nimi";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix2container.follows = "nimi/nix2container";

    # Base container modules — this is what we consume
    nix2gpu = {
      url = "github:fleek-sh/nix2gpu";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.systems.follows = "systems";
      # n.b. override nix2gpu's nimi to use our fixed version
      inputs.nimi.follows = "nimi";
    };

    # TODO: Sensenet — nix-compile infrastructure for Straylight stack
    # Provides LLVM/CUDA build infrastructure, TensorRT integration
    # Re-enable when repo is available:
    # sensenet = {
    #   url = "github:straylight-software/sensenet/nix-compile/strict-straylight";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  nixConfig = {
    extra-substituters = [ "https://weyl-ai.cachix.org" ];
    extra-trusted-public-keys = [
      "weyl-ai.cachix.org-1:cR0SpSAPw7wejZ21ep4SLojE77gp5F2os260eEWqTTw="
    ];
  };

  outputs =
    { flake-parts, import-tree, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.nix2gpu.flakeModule
        (import-tree [
          ./examples
          ./dev
        ])
      ];

      perSystem =
        {
          config,
          pkgs,
          lib,
          self',
          inputs',
          system,
          ...
        }:
        let
          # GHC 9.12 for StrictData and latest language features
          hpkgs = pkgs.haskell.packages.ghc912;

          # The gateway package
          straylightPackage = pkgs.callPackage ./gateway/package.nix {
            haskellPackages = hpkgs;
          };

        in
        {
          # ════════════════════════════════════════════════════════════════════
          #                                              // packages
          # ════════════════════════════════════════════════════════════════════

          packages = {
            default = straylightPackage;
            straylight-llm = straylightPackage;
          };

          # ════════════════════════════════════════════════════════════════════
          #                                              // treefmt
          # ════════════════════════════════════════════════════════════════════

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt = {
                enable = true;
                strict = true;
              };
              ormolu.enable = true;
              hlint.enable = true;
            };
          };

          # ════════════════════════════════════════════════════════════════════
          #                                              // devshell
          # ════════════════════════════════════════════════════════════════════

          devShells.default = pkgs.mkShell {
            inputsFrom = [
              config.treefmt.build.devShell
            ];

            packages = [
              # Haskell
              hpkgs.ghc
              hpkgs.cabal-install
              hpkgs.haskell-language-server
              hpkgs.ghcid
              hpkgs.hlint
              hpkgs.ormolu

              # PureScript (Phase 6 - Frontend)
              pkgs.purescript
              pkgs.spago
              pkgs.esbuild
              pkgs.nodejs

              # Tauri (Desktop app)
              pkgs.rustc
              pkgs.cargo
              pkgs.pkg-config
              pkgs.gtk3
              pkgs.webkitgtk_4_1
              pkgs.libsoup_3
              pkgs.openssl

              # Lean4
              pkgs.lean4

              # General
              pkgs.pkg-config
              pkgs.curl
              pkgs.jq
              pkgs.httpie

              # Build dependencies
              pkgs.zlib

              # Container tools
              pkgs.docker
              pkgs.podman
              inputs'.nix2container.packages.skopeo-nix2container
            ];

            shellHook = ''
              echo ""
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "                                                   // straylight-llm //"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              echo "  CGP-first OpenAI gateway with verified types"
              echo ""
              echo "════════════════════════════════════════════════════════════════════════════════"
              echo "                                                   // gateway commands //"
              echo "════════════════════════════════════════════════════════════════════════════════"
              echo ""
              echo "  nix build .#basic         Build basic container (OpenRouter only)"
              echo "  nix build .#with-cgp      Build CGP-first container"
              echo "  nix build .#straylight-llm Build the gateway binary"
              echo ""
              echo "  cabal build               Build gateway locally"
              echo "  cabal run straylight-llm  Run gateway locally"
              echo "  ghcid                     Watch mode"
              echo ""
              echo "════════════════════════════════════════════════════════════════════════════════"
              echo "                                                  // frontend commands //"
              echo "════════════════════════════════════════════════════════════════════════════════"
              echo ""
              echo "  cd frontend && spago build     Build PureScript frontend"
              echo "  cd frontend && spago bundle    Bundle for production"
              echo "  cd frontend && spago build -w  Watch mode"
              echo ""
              echo "════════════════════════════════════════════════════════════════════════════════"
              echo "                                                  // desktop commands //"
              echo "════════════════════════════════════════════════════════════════════════════════"
              echo ""
              echo "  cd frontend && npm run tauri:dev    Run Tauri dev mode"
              echo "  cd frontend && npm run tauri:build  Build desktop app"
              echo ""
              echo "════════════════════════════════════════════════════════════════════════════════"
              echo "                                                      // other commands //"
              echo "════════════════════════════════════════════════════════════════════════════════"
              echo ""
              echo "  nix fmt                   Format all code"
              echo ""
            '';
          };
        };
    };
}
