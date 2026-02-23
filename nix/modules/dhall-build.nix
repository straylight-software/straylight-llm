# nix/modules/dhall-build.nix
#
# Dhall BUILD integration for straylight-llm.
#
# Reads typed Dhall BUILD files and produces Nix derivations.
# This implements the "no globs, no strings" principle from aleph cube.
#
# Key concepts from Continuity.lean:
#   - Every file is explicit (no globs)
#   - Every flag is typed (not "-O2" strings)
#   - Build scripts are deterministic functions of typed inputs
#
{ inputs, ... }:
{
  _class = "flake";

  config.perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # ════════════════════════════════════════════════════════════════════════
      #                                               // dhall evaluation
      # ════════════════════════════════════════════════════════════════════════

      # Evaluate a Dhall expression to JSON
      evalDhall =
        {
          dhallFile,
          dhallDir ? ./../../dhall,
        }:
        let
          jsonOutput =
            pkgs.runCommand "dhall-to-json"
              {
                nativeBuildInputs = [ pkgs.dhall-json ];
              }
              ''
                cd ${dhallDir}
                dhall-to-json < ${dhallFile} > $out
              '';
        in
        builtins.fromJSON (builtins.readFile jsonOutput);

      # ════════════════════════════════════════════════════════════════════════
      #                                               // straylight-llm config
      # ════════════════════════════════════════════════════════════════════════

      # Read the straylight-llm.dhall configuration
      # This is evaluated at build time, producing typed configuration
      straylightConfig = evalDhall {
        dhallFile = "straylight-llm.dhall";
        dhallDir = ./../../dhall;
      };

      # ════════════════════════════════════════════════════════════════════════
      #                                               // source manifest
      # ════════════════════════════════════════════════════════════════════════

      # Extract the explicit file list from Dhall config
      # No globs - every file is explicitly listed
      sourceFiles = map (p: p._path) (straylightConfig.sourceManifest.files or [ ]);
      testFiles = map (p: p._path) (straylightConfig.testManifest.files or [ ]);

      # All explicit sources (for hermetic builds)
      allSources = sourceFiles ++ testFiles;

      # ════════════════════════════════════════════════════════════════════════
      #                                               // typed build options
      # ════════════════════════════════════════════════════════════════════════

      # Convert Dhall typed options to GHC flags
      # These are ADTs, not strings - type safety preserved
      optLevelToFlag =
        opt:
        if opt == "O0" then
          "-O0"
        else if opt == "O1" then
          "-O1"
        else if opt == "O2" then
          "-O2"
        else
          "-O1";

      ghcVersionToPackage =
        ver:
        if ver == "GHC948" then
          pkgs.haskell.compiler.ghc948
        else if ver == "GHC9101" then
          pkgs.haskell.compiler.ghc9101
        else if ver == "GHC9103" then
          pkgs.haskell.compiler.ghc9103
        else if ver == "GHC912" then
          pkgs.haskell.compiler.ghc912
        else
          pkgs.haskell.compiler.ghc912;

      warningFlagToGhc =
        w:
        if w == "Wall" then
          "-Wall"
        else if w == "Wcompat" then
          "-Wcompat"
        else if w == "Werror" then
          "-Werror"
        else if w == "Wno_unused_imports" then
          "-Wno-unused-imports"
        else if w == "Wno_name_shadowing" then
          "-Wno-name-shadowing"
        else
          "";

      extensionToGhc =
        e:
        if e == "OverloadedStrings" then
          "-XOverloadedStrings"
        else if e == "RecordWildCards" then
          "-XRecordWildCards"
        else if e == "StrictData" then
          "-XStrictData"
        else if e == "DataKinds" then
          "-XDataKinds"
        else if e == "TypeOperators" then
          "-XTypeOperators"
        else if e == "DeriveGeneric" then
          "-XDeriveGeneric"
        else if e == "DerivingStrategies" then
          "-XDerivingStrategies"
        else if e == "LambdaCase" then
          "-XLambdaCase"
        else if e == "BangPatterns" then
          "-XBangPatterns"
        else if e == "NamedFieldPuns" then
          "-XNamedFieldPuns"
        else if e == "GHC2021" then
          "-XGHC2021"
        else
          "";

      # Build GHC options from Dhall config
      haskellOpts = straylightConfig.haskellOpts or { };
      ghcFlags = lib.concatStringsSep " " (
        [ (optLevelToFlag (haskellOpts.optLevel or "O2")) ]
        ++ (map warningFlagToGhc (haskellOpts.warnings or [ ]))
        ++ (map extensionToGhc (haskellOpts.extensions or [ ]))
        ++ (lib.optional (haskellOpts.threaded or true) "-threaded")
        ++ (lib.optional (haskellOpts.rtsopts or true) "-rtsopts")
      );

      # ════════════════════════════════════════════════════════════════════════
      #                                               // build verification
      # ════════════════════════════════════════════════════════════════════════

      # Verify that all declared source files exist
      # This is a hermetic check: if manifest says a file exists, it must
      verifySourceManifest =
        pkgs.runCommand "verify-dhall-manifest"
          {
            src = ./../../.;
          }
          ''
            cd $src

            # Check each declared file exists
            ${lib.concatMapStringsSep "\n" (f: ''
              if [ ! -f "${f}" ]; then
                echo "ERROR: Declared file missing: ${f}"
                exit 1
              fi
            '') sourceFiles}

            echo "All ${toString (builtins.length sourceFiles)} source files verified"
            mkdir -p $out
            echo "verified" > $out/status
            echo "${lib.concatStringsSep "\n" sourceFiles}" > $out/manifest.txt
          '';

      # ════════════════════════════════════════════════════════════════════════
      #                                               // exports
      # ════════════════════════════════════════════════════════════════════════

    in
    {
      # Export verification derivation as a package
      packages.dhall-verify = verifySourceManifest;

      # Export Dhall config as JSON for inspection
      packages.dhall-config =
        pkgs.runCommand "dhall-config-json"
          {
            nativeBuildInputs = [ pkgs.dhall-json ];
          }
          ''
            mkdir -p $out
            cd ${./../../dhall}
            dhall-to-json < straylight-llm.dhall > $out/straylight-llm.json
            echo "Exported Dhall config to JSON"
          '';

      # Export a shell that includes Dhall tools
      devShells.dhall = pkgs.mkShell {
        packages = [
          pkgs.dhall
          pkgs.dhall-json
          pkgs.dhall-lsp-server
        ];

        shellHook = ''
          echo ""
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "                                                   // dhall BUILD files //"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo ""
          echo "  Typed build configuration from Dhall"
          echo ""
          echo "════════════════════════════════════════════════════════════════════════════════"
          echo "                                                       // commands //"
          echo "════════════════════════════════════════════════════════════════════════════════"
          echo ""
          echo "  cd dhall && dhall type < straylight-llm.dhall    Type-check config"
          echo "  cd dhall && dhall-to-json < straylight-llm.dhall Export to JSON"
          echo "  nix build .#dhall-verify                         Verify source manifest"
          echo ""

          cd dhall 2>/dev/null || true
        '';
      };
    };
}
