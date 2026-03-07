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

    # Haskell OpenAPI property testing (private repo, use SSH)
    haskemathesis = {
      url = "git+ssh://git@github.com/weyl-ai/haskemathesis.git";
      flake = false;
    };

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

    # Sensenet — aleph cube build system with Buck2 + Dhall
    # Provides typed BUILD files, remote execution, hermetic builds
    sensenet = {
      url = "git+ssh://git@github.com/straylight-software/sensenet";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nix-compile.follows = "nix-compile";
      inputs.buck2-prelude.follows = "buck2-prelude";
      inputs.nvidia-sdk.follows = "nvidia-sdk";
    };

    # nix-compile — type inference for Nix (sensenet dependency)
    nix-compile = {
      url = "git+ssh://git@github.com/straylight-software/nix-compile";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Buck2 prelude (sensenet dependency)
    buck2-prelude = {
      url = "git+ssh://git@github.com/weyl-ai/straylight-buck2-prelude";
      flake = false;
    };

    # NVIDIA SDK (sensenet dependency, optional)
    nvidia-sdk = {
      url = "git+ssh://git@github.com/weyl-ai/nvidia-sdk";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # crane — Rust build tool for tokenizers-cpp
    crane = {
      url = "github:ipetkov/crane";
    };

    # rust-overlay — Rust toolchain for tokenizers-cpp
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
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
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.nix2gpu.flakeModule
        # Use our fixed sensenet module (patches lowercase function calls bug)
        (import ./nix/modules/sensenet-fixed.nix { inherit inputs; })
        # Dhall BUILD file integration (typed build configs)
        (import ./nix/modules/dhall-build.nix { inherit inputs; })
        (import-tree [
          ./examples
          ./dev
        ])
      ];

      # ════════════════════════════════════════════════════════════════════════════
      #                                              // nixos modules
      # ════════════════════════════════════════════════════════════════════════════

      flake = {
        nixosModules.default = ./nix/modules/straylight-llm.nix;
        nixosModules.straylight-llm = ./nix/modules/straylight-llm.nix;
      };

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
          # Rust toolchain for tokenizers-cpp
          rustOverlay = import inputs.rust-overlay;
          pkgsWithRust = import inputs.nixpkgs {
            inherit system;
            overlays = [ rustOverlay ];
          };
          rustToolchain = pkgsWithRust.rust-bin.stable.latest.default;
          craneLib = (inputs.crane.mkLib pkgsWithRust).overrideToolchain rustToolchain;

          # tokenizers-cpp with pre-built Rust library (for SIGIL FFI)
          tokenizers-cpp = pkgs.callPackage ./nix/tokenizers-cpp.nix {
            inherit craneLib;
          };

          # GHC 9.12 for StrictData and latest language features
          # Overlay local packages (effect-monad, io-uring, haskemathesis) into the package set
          hpkgs = pkgs.haskell.packages.ghc912.override {
            overrides = hself: hsuper: {
              # effect-monad 0.9 with GHC 9.12 support (QualifiedDo)
              effect-monad = hself.callCabal2nix "effect-monad" ./effect-monad-912 { };

              # haskemathesis - OpenAPI property testing (from flake input via SSH)
              haskemathesis = hself.callCabal2nix "haskemathesis" inputs.haskemathesis { };

              # io-uring bindings for evring-wai backend
              # n.b. extra-libraries: uring in cabal requires passing liburing as 'uring'
              io-uring = hself.callCabal2nix "io-uring" ./io-uring {
                uring = pkgs.liburing;
              };

              # zeromq4-haskell with libzmq4 from pkgs
              # Override the pkgconfig dependency name (cabal2nix generates 'zeromq' but we need zmq4)
              zeromq4-haskell =
                pkgs.haskell.lib.overrideCabal (hself.callHackage "zeromq4-haskell" "0.8.0" { })
                  (old: {
                    libraryPkgconfigDepends = [ pkgs.zeromq ];
                  });

              # straylight-llm gateway (depends on effect-monad, io-uring, haskemathesis, zeromq4-haskell, tokenizers-cpp)
              straylight-llm =
                let
                  basePkg = hself.callCabal2nix "straylight-llm" ./gateway { };
                in
                pkgs.haskell.lib.overrideCabal basePkg (old: {
                  librarySystemDepends = (old.librarySystemDepends or [ ]) ++ [
                    pkgs.liburing
                    pkgs.zeromq
                    tokenizers-cpp
                  ];
                  # Set up library/include paths for tokenizers-cpp C++ FFI
                  preConfigure = ''
                    export LIBRARY_PATH="${tokenizers-cpp}/lib''${LIBRARY_PATH:+:$LIBRARY_PATH}"
                    export LD_LIBRARY_PATH="${tokenizers-cpp}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
                    export CFLAGS="-I${tokenizers-cpp}/include $CFLAGS"
                    export CXXFLAGS="-I${tokenizers-cpp}/include $CXXFLAGS"
                  '';
                });
            };
          };

          # The gateway package from our overlay
          straylightPackage = hpkgs.straylight-llm;

        in
        {
          # ════════════════════════════════════════════════════════════════════
          #                                              // sensenet project
          # ════════════════════════════════════════════════════════════════════

          sensenet.projects.gateway = {
            src = ./.;
            targets = [
              "//gateway:straylight-llm"
              "//gateway:straylight-llm-test"
            ];
            toolchain = {
              haskell = {
                enable = true;
                ghcpackages = hpkgs;
                packages = hp: [
                  # Core
                  hp.aeson
                  hp.base16-bytestring
                  hp.bytestring
                  hp.containers
                  hp.text
                  hp.time
                  hp.stm
                  hp.mtl
                  hp.transformers
                  hp.vector
                  # Parsing
                  hp.megaparsec
                  # HTTP
                  hp.http-client
                  hp.http-client-tls
                  hp.http-types
                  hp.wai
                  hp.warp
                  # Servant
                  hp.servant
                  hp.servant-server
                  # Crypto (for discharge proofs)
                  hp.crypton
                  hp.memory
                  # UUID
                  hp.uuid
                  # Testing
                  hp.hedgehog
                  hp.tasty
                  hp.tasty-hedgehog
                  hp.tasty-hunit
                ];
              };
            };
            devshellpackages = [
              pkgs.dhall
              pkgs.dhall-json
              pkgs.buck2
            ];
          };

          # ════════════════════════════════════════════════════════════════════
          #                                              // packages
          # ════════════════════════════════════════════════════════════════════

          packages = {
            default = straylightPackage;
            straylight-llm = straylightPackage;
          };

          # ════════════════════════════════════════════════════════════════════
          #                                              // apps (nix run)
          # ════════════════════════════════════════════════════════════════════

          apps =
            let
              # Gateway binary path (built via cabal in devShell)
              # n.b. effect-monad and io-uring not in nixpkgs haskellPackages,
              # so we use pre-built binary from cabal
              gatewayBinary = "gateway/dist-newstyle/build/x86_64-linux/ghc-9.12.2/straylight-llm-0.1.0.0/x/straylight-llm/build/straylight-llm/straylight-llm";

              # Gateway runner with configurable backend
              mkGatewayApp =
                {
                  name,
                  env ? { },
                }:
                {
                  type = "app";
                  program = toString (
                    pkgs.writeShellScript "run-${name}" ''
                      set -euo pipefail
                      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${v}") env)}

                      # Find binary (check relative and absolute paths)
                      BINARY=""
                      if [[ -x "./${gatewayBinary}" ]]; then
                        BINARY="./${gatewayBinary}"
                      elif [[ -x "${gatewayBinary}" ]]; then
                        BINARY="${gatewayBinary}"
                      fi

                      if [[ -z "$BINARY" ]]; then
                        echo ""
                        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        echo "  Gateway binary not found. Building..."
                        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        echo ""
                        cd gateway
                        ${hpkgs.cabal-install}/bin/cabal build
                        cd ..
                        BINARY="./${gatewayBinary}"
                      fi

                      exec "$BINARY" "$@"
                    ''
                  );
                };

              # Frontend dev server
              # n.b. Must be run from the straylight-llm repo root directory
              # Uses npx spago@next for spago.yaml (new format) support
              frontendApp = {
                type = "app";
                program = toString (
                  pkgs.writeShellScript "run-frontend" ''
                    set -euo pipefail
                    export PATH="${pkgs.purescript}/bin:${pkgs.esbuild}/bin:${pkgs.nodejs}/bin:$PATH"

                    # Verify we're in the repo root
                    if [[ ! -d "frontend" ]]; then
                      echo "Error: Must run from straylight-llm repo root directory"
                      exit 1
                    fi

                    cd frontend
                    echo ""
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "                                                   // straylight-web //"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo ""
                    echo "  Building PureScript frontend..."
                    npx spago@next build
                    echo ""
                    echo "  Bundling for production..."
                    npx spago@next bundle --bundle-type app --outfile dist/app.js
                    echo ""
                    echo "  Starting dev server on http://localhost:1420"
                    echo ""
                    ${pkgs.python3}/bin/python3 -m http.server 1420 --directory .
                  ''
                );
              };

              # Full stack runner (gateway + frontend in parallel)
              # n.b. Must be run from the straylight-llm repo root directory
              stackApp = {
                type = "app";
                program = toString (
                  pkgs.writeShellScript "run-stack" ''
                    set -euo pipefail

                    # Verify we're in the repo root
                    if [[ ! -f "flake.nix" ]] || [[ ! -d "gateway" ]] || [[ ! -d "frontend" ]]; then
                      echo "Error: Must run from straylight-llm repo root directory"
                      exit 1
                    fi

                    # Find or build gateway binary
                    BINARY=""
                    if [[ -x "./${gatewayBinary}" ]]; then
                      BINARY="./${gatewayBinary}"
                    else
                      echo ""
                      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                      echo "  Gateway binary not found. Building..."
                      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                      echo ""
                      cd gateway
                      ${hpkgs.cabal-install}/bin/cabal build
                      cd ..
                      BINARY="./${gatewayBinary}"
                    fi

                    GATEWAY_PID=""
                    FRONTEND_PID=""
                    cleanup() {
                      echo ""
                      echo "Shutting down..."
                      [[ -n "$GATEWAY_PID" ]] && kill $GATEWAY_PID 2>/dev/null || true
                      [[ -n "$FRONTEND_PID" ]] && kill $FRONTEND_PID 2>/dev/null || true
                      wait 2>/dev/null || true
                    }
                    trap cleanup EXIT INT TERM

                    echo ""
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "                                                   // straylight stack //"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo ""
                    echo "  Gateway:  http://localhost:8080  (io_uring multi-core)"
                    echo "  Frontend: http://localhost:1420"
                    echo "  SSE:      http://localhost:8080/v1/events"
                    echo ""
                    echo "  Press Ctrl+C to stop"
                    echo ""

                    # Start gateway with io_uring single-core
                    # Multi-core requires increased ulimit -l (locked memory)
                    # Set USE_URING_MC=1 for multi-core if you have sufficient ulimit -l
                    # Set USE_WARP=1 to force Warp backend (for VMs/containers without io_uring)
                    USE_URING=1 "$BINARY" &
                    GATEWAY_PID=$!

                    # Build and serve frontend (from repo root)
                    # Uses npx spago@next for spago.yaml (new format) support
                    export PATH="${pkgs.purescript}/bin:${pkgs.esbuild}/bin:${pkgs.nodejs}/bin:$PATH"
                    pushd frontend >/dev/null
                    echo "  [frontend] Building PureScript..."
                    npx spago@next build
                    echo "  [frontend] Bundling..."
                    npx spago@next bundle --bundle-type app --outfile dist/app.js
                    echo "  [frontend] Starting server on http://localhost:1420"
                    ${pkgs.python3}/bin/python3 -m http.server 1420 --directory . &
                    FRONTEND_PID=$!
                    popd >/dev/null

                    wait $GATEWAY_PID $FRONTEND_PID
                  ''
                );
              };

            in
            {
              # Default: run gateway with Warp
              default = mkGatewayApp { name = "gateway"; };
              gateway = mkGatewayApp { name = "gateway"; };

              # io_uring backends
              gateway-uring = mkGatewayApp {
                name = "gateway-uring";
                env = {
                  USE_URING = "1";
                };
              };
              gateway-uring-mc = mkGatewayApp {
                name = "gateway-uring-mc";
                env = {
                  USE_URING_MC = "1";
                };
              };

              # Frontend
              frontend = frontendApp;

              # Full stack (gateway + frontend)
              # Uses Warp by default (safe for VMs/containers)
              # Set USE_URING_MC=1 env var to enable io_uring multi-core
              stack = stackApp;
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

              # Dhall (typed build configs)
              pkgs.dhall
              pkgs.dhall-json
              pkgs.dhall-lsp-server

              # General
              pkgs.pkg-config
              pkgs.curl
              pkgs.jq
              pkgs.httpie

              # Build dependencies
              pkgs.zlib
              pkgs.liburing # io_uring for evring-wai backend
              pkgs.zeromq # ZMQ for SIGIL frame egress
              tokenizers-cpp # HuggingFace tokenizers for SIGIL

              # Container tools
              pkgs.docker
              pkgs.podman
              inputs'.nix2container.packages.skopeo-nix2container
            ];

            shellHook = ''
              # ZMQ and liburing pkg-config paths for zeromq4-haskell and io-uring
              export PKG_CONFIG_PATH="${pkgs.liburing}/lib/pkgconfig:${pkgs.zeromq}/lib/pkgconfig:$PKG_CONFIG_PATH"

              # tokenizers-cpp paths for SIGIL FFI
              export LIBRARY_PATH="${tokenizers-cpp}/lib''${LIBRARY_PATH:+:$LIBRARY_PATH}"
              export LD_LIBRARY_PATH="${tokenizers-cpp}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
              export CFLAGS="-I${tokenizers-cpp}/include $CFLAGS"
              export CXXFLAGS="-I${tokenizers-cpp}/include $CXXFLAGS"

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
              echo "                                                  // dhall commands //"
              echo "════════════════════════════════════════════════════════════════════════════════"
              echo ""
              echo "  cd dhall && dhall type < straylight-llm.dhall    Type-check BUILD config"
              echo "  cd dhall && dhall-to-json < straylight-llm.dhall Export to JSON"
              echo "  nix build .#dhall-verify                         Verify source manifest"
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
