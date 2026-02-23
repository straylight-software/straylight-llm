# nix/modules/sensenet-fixed.nix
#
# Fixed sensenet flake module that patches the toolchainlib case mismatch.
#
# The upstream sensenet has a bug where toolchains.nix defines functions
# with camelCase (mkBuckconfigLocal) but flake-module.nix calls them with
# lowercase (mkbuckconfiglocal).
#
# This module wraps sensenet's options and provides a fixed implementation.
#
{ inputs, ... }:
{
  _class = "flake";

  imports = [
    # Import sensenet's options (defines sensenet.projects, etc.)
    (import "${inputs.sensenet}/nix/modules/flake/sensenet/options.nix")
  ];

  config.perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Import the toolchainlib - we use the original camelCase function names directly
      toolchainlib = import "${inputs.sensenet}/nix/modules/flake/sensenet/toolchains.nix" {
        inherit lib pkgs;
      };

      # Re-export mkproject with the fixed toolchainlib
      mkproject =
        {
          name,
          src,
          targets ? [ "//..." ],
          prelude ? null,
          toolchain ? { },
          remoteexecution ? { },
          extrabuckconfigsections ? "",
          extrapackages ? [ ],
          devshellpackages ? [ ],
          devshellhook ? "",
          installbinaries ? true,
          installphase ? null,
          ...
        }:
        let
          # ── Resolve toolchain packages ─────────────────────────────────────────
          cxxenabled = toolchain.cxx.enable or true;
          haskellenabled = toolchain.haskell.enable or false;
          rustenabled = toolchain.rust.enable or false;
          leanenabled = toolchain.lean.enable or false;
          pythonenabled = toolchain.python.enable or false;
          nvenabled = toolchain.nv.enable or false;
          purescriptenabled = toolchain.purescript.enable or false;

          # ── Remote execution config ────────────────────────────────────────────
          reenabled = remoteexecution.enable or false;
          rescheduler = remoteexecution.scheduler or "localhost";
          reschedulerport = remoteexecution.schedulerport or 50051;
          recas = remoteexecution.cas or "localhost";
          recasport = remoteexecution.casport or 50052;
          retls = remoteexecution.tls or true;
          reinstancename = remoteexecution.instancename or "main";

          llvmpackages = toolchain.cxx.llvmpackages or pkgs.llvmPackages_19;
          hspackages = toolchain.haskell.ghcpackages or pkgs.haskellPackages;
          hspkgsfn = toolchain.haskell.packages or (_hp: [ ]);
          ghcversion = hspackages.ghc.version;
          ghc = hspackages.ghcWithPackages hspkgsfn;
          hooglewithdb = hspackages.hoogleWithPackages hspkgsfn;
          python = toolchain.python.package or pkgs.python312;
          inherit (pkgs.python3Packages) pybind11;
          nvidia-sdk = inputs.nvidia-sdk.packages.${pkgs.system}.default or null;

          # ── Generate buckconfig.local (using fixed toolchainlib) ───────────────
          # Note: mkBuckconfigLocal uses camelCase arg names, sections use camelCase too
          buckconfiglocal = toolchainlib.mkBuckconfigLocal {
            cxx = lib.optionalString cxxenabled (toolchainlib.mkCxxSection { llvmPackages = llvmpackages; });
            haskell = lib.optionalString haskellenabled (
              toolchainlib.mkHaskellSection {
                inherit ghc;
                ghcVersion = ghcversion;
              }
            );
            rust = lib.optionalString rustenabled (toolchainlib.mkRustSection { });
            lean = lib.optionalString leanenabled (toolchainlib.mkLeanSection { });
            python = lib.optionalString pythonenabled (
              toolchainlib.mkPythonSection { inherit python pybind11; }
            );
            nv = lib.optionalString (nvenabled && nvidia-sdk != null) (
              toolchainlib.mkNvSection {
                inherit nvidia-sdk;
                inherit (llvmpackages) clang-unwrapped;
                mdspan = pkgs.callPackage "${inputs.sensenet}/nix/packages/mdspan.nix" { };
              }
            );
            purescript = lib.optionalString purescriptenabled (toolchainlib.mkPureScriptSection { });
            remoteExecution = lib.optionalString reenabled (
              toolchainlib.mkRemoteExecutionSection {
                scheduler = rescheduler;
                schedulerPort = reschedulerport;
                cas = recas;
                casPort = recasport;
                tls = retls;
                instanceName = reinstancename;
              }
            );
            extra = extrabuckconfigsections;
          };

          buckconfiglocalfile = pkgs.writeText "buckconfig.local" buckconfiglocal;

          # ── Prelude path ───────────────────────────────────────────────────────
          preludepath = if prelude != null then prelude else inputs.buck2-prelude;

          # ── Toolchain packages ─────────────────────────────────────────────────
          toolchainpackages = [
            pkgs.buck2
          ]
          ++ lib.optionals cxxenabled [
            llvmpackages.clang
            llvmpackages.lld
            llvmpackages.llvm
          ]
          ++ lib.optionals haskellenabled [
            ghc
            hspackages.haskell-language-server
            hooglewithdb
          ]
          ++ lib.optionals rustenabled [
            pkgs.rustc
            pkgs.cargo
            pkgs.clippy
            pkgs.rustfmt
            pkgs.rust-analyzer
          ]
          ++ lib.optionals leanenabled [ pkgs.lean4 ]
          ++ lib.optionals pythonenabled [ python ]
          ++ lib.optionals purescriptenabled [
            pkgs.purescript
            pkgs.spago
            pkgs.nodejs
          ]
          ++ extrapackages;

          # ── Shell hook ─────────────────────────────────────────────────────────
          shellhook = ''
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "                                                 // sensenet: ${name} //"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "  Buck2 build system with typed toolchains"
            echo ""
            echo "  Targets: ${lib.concatStringsSep " " targets}"
            echo ""
            echo "════════════════════════════════════════════════════════════════════════════════"
            echo "                                                       // commands //"
            echo "════════════════════════════════════════════════════════════════════════════════"
            echo ""
            echo "  buck2 build //gateway:straylight-llm    Build the gateway"
            echo "  buck2 test //gateway:straylight-llm-test Run tests"
            echo "  buck2 run //gateway:straylight-llm      Run the gateway"
            echo ""

            # Set up prelude symlink
            mkdir -p nix/build
            ln -sf ${preludepath} nix/build/prelude 2>/dev/null || true

            # Generate buckconfig.local
            cp -f ${buckconfiglocalfile} .buckconfig.local 2>/dev/null || true

            ${devshellhook}
          '';

          # ── Package derivation ─────────────────────────────────────────────────
          package = pkgs.stdenvNoCC.mkDerivation {
            inherit name;
            inherit src;

            __noChroot = true;

            nativeBuildInputs = toolchainpackages ++ [
              pkgs.git
              pkgs.cacert
            ];

            buildPhase = ''
              export HOME=$TMPDIR

              mkdir -p nix/build
              ln -sf ${preludepath} nix/build/prelude

              cp ${buckconfiglocalfile} .buckconfig.local

              buck2 build ${lib.concatStringsSep " " targets}
            '';

            installPhase =
              if installphase != null then
                installphase
              else
                ''
                  mkdir -p $out

                  ${lib.optionalString installbinaries ''
                    mkdir -p $out/bin
                    find buck-out/v2/gen -type f -executable -not -name "*.so" -not -name "*.a" 2>/dev/null | while read bin; do
                      if file "$bin" | grep -q "ELF.*executable"; then
                        install -m 755 "$bin" "$out/bin/" 2>/dev/null || true
                      fi
                    done
                  ''}

                  echo "${lib.concatStringsSep " " targets}" > $out/.sensenet-targets
                '';

            dontConfigure = true;
            dontFixup = true;
          };

          # ── Development shell ──────────────────────────────────────────────────
          devshell = pkgs.mkShellNoCC {
            name = "${name}-dev";

            inputsFrom = [ package ];
            packages = devshellpackages ++ [
              pkgs.jq
              pkgs.ripgrep
              pkgs.fd
            ];

            shellHook = shellhook;
          };
        in
        {
          inherit package devshell buckconfiglocalfile;
        };

      # ── Build all declared projects ──────────────────────────────────────────
      sensenetprojects = lib.mapAttrs (
        name: proj: mkproject (proj // { inherit name; })
      ) config.sensenet.projects;
    in
    {
      sensenet.mkproject = mkproject;

      packages =
        lib.mapAttrs' (name: proj: lib.nameValuePair "sensenet-${name}" proj.package) sensenetprojects
        // lib.mapAttrs' (name: proj: lib.nameValuePair "buck2-${name}" proj.package) sensenetprojects;

      devShells =
        lib.mapAttrs' (name: proj: lib.nameValuePair "sensenet-${name}" proj.devshell) sensenetprojects
        // lib.mapAttrs' (name: proj: lib.nameValuePair "buck2-${name}" proj.devshell) sensenetprojects;
    };
}
