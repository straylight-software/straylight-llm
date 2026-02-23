-- dhall/Build.dhall
--
-- Target -> BuildScript
--
-- Generates shell scripts that compile Haskell targets using Cabal.
-- Adapted from aleph cube architecture.
--
-- Key principle: Build scripts are deterministic functions of typed inputs.

let T = ./Target.dhall
let P = ./Platform.dhall

let Prelude = https://prelude.dhall-lang.org/v23.0.0/package.dhall

let map = Prelude.List.map
let concatSep = Prelude.Text.concatSep
let concatMapSep = Prelude.Text.concatMapSep

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Build script output
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let BuildScript = { script : Text }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Helpers
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let pathToText : T.Path -> Text = \(p : T.Path) -> p._path
let nameToText : T.Name -> Text = \(n : T.Name) -> n._name

let spaceSep : List Text -> Text = concatSep " "

-- Convert typed GHC options to flags
let optLevelFlag : T.OptLevel -> Text = \(o : T.OptLevel) ->
    merge
        { O0 = "-O0"
        , O1 = "-O1"
        , O2 = "-O2"
        }
        o

let warningFlagToText : T.WarningFlag -> Text = \(w : T.WarningFlag) ->
    merge
        { Wall = "-Wall"
        , Wcompat = "-Wcompat"
        , Werror = "-Werror"
        , Wno_unused_imports = "-Wno-unused-imports"
        , Wno_name_shadowing = "-Wno-name-shadowing"
        }
        w

let extensionToText : T.Extension -> Text = \(e : T.Extension) ->
    merge
        { OverloadedStrings = "-XOverloadedStrings"
        , RecordWildCards = "-XRecordWildCards"
        , StrictData = "-XStrictData"
        , DataKinds = "-XDataKinds"
        , TypeOperators = "-XTypeOperators"
        , DeriveGeneric = "-XDeriveGeneric"
        , DerivingStrategies = "-XDerivingStrategies"
        , LambdaCase = "-XLambdaCase"
        , BangPatterns = "-XBangPatterns"
        , NamedFieldPuns = "-XNamedFieldPuns"
        , GHC2021 = "-XGHC2021"
        }
        e

let ghcVersionFlag : T.GhcVersion -> Text = \(v : T.GhcVersion) ->
    merge
        { GHC948 = "-w ghc-9.4.8"
        , GHC9101 = "-w ghc-9.10.1"
        , GHC9103 = "-w ghc-9.10.3"
        , GHC912 = "-w ghc-9.12"
        }
        v

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Haskell/Cabal build
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let buildHaskell
    : T.Name -> T.SourceManifest -> T.HaskellOpts -> List T.Dep -> P.HaskellToolchain -> BuildScript
    = \(name : T.Name) ->
      \(srcs : T.SourceManifest) ->
      \(opts : T.HaskellOpts) ->
      \(deps : List T.Dep) ->
      \(tc : P.HaskellToolchain) ->
        let outName = nameToText name
        let optLevel = optLevelFlag opts.optLevel
        let warnings = spaceSep (map T.WarningFlag Text warningFlagToText opts.warnings)
        let extensions = spaceSep (map T.Extension Text extensionToText opts.extensions)
        let ghcVersion = ghcVersionFlag opts.ghcVersion
        let threadedFlag = if opts.threaded then "-threaded" else ""
        let rtsOptsFlag = if opts.rtsopts then "-rtsopts" else ""

        -- Nix deps handling
        let nixDeps = concatMapSep " "
            T.Dep
            (\(d : T.Dep) -> merge
                { Local = \(l : T.Label) ->
                    merge
                        { Some = \(pkg : Text) -> "${pkg}:${l.name}"
                        , None = l.name
                        }
                        l.package
                , Nix = \(f : T.FlakeRef) -> "${f.flake}#${f.attr}"
                }
                d)
            deps

        in { script =
''
#!/usr/bin/env bash
# Generated build script for ${outName}
# DO NOT EDIT - this file is generated from Dhall
set -euo pipefail

# Toolchain paths
GHC="${pathToText tc.ghc}"
CABAL="${pathToText tc.cabal}"

# Build with Cabal
"$CABAL" build \
    ${ghcVersion} \
    --ghc-options="${optLevel} ${warnings} ${extensions} ${threadedFlag} ${rtsOptsFlag}" \
    all

# Copy output
cp -L "$(cabal list-bin ${outName})" "$OUT"
''
        }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Container build (via Nix)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let containerBaseImage : T.ContainerBase -> Text = \(b : T.ContainerBase) ->
    merge
        { Scratch = "scratch"
        , Alpine = "alpine:latest"
        , Distroless = "gcr.io/distroless/static:nonroot"
        }
        b

let buildContainer
    : T.Name -> T.ContainerOpts -> T.Path -> BuildScript
    = \(name : T.Name) ->
      \(opts : T.ContainerOpts) ->
      \(binary : T.Path) ->
        let outName = nameToText name
        let baseImage = containerBaseImage opts.base
        let ports = concatMapSep " " Natural (\(p : Natural) -> "--port=${Natural/show p}") opts.exposedPorts

        in { script =
''
#!/usr/bin/env bash
# Generated container build script for ${outName}
# DO NOT EDIT - this file is generated from Dhall
set -euo pipefail

# Build container with nix
nix build .#${outName}

# Copy to output
cp -L result "$OUT"
''
        }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Test build
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let buildTest
    : T.Name -> T.SourceManifest -> T.HaskellOpts -> List T.Dep -> P.HaskellToolchain -> BuildScript
    = \(name : T.Name) ->
      \(srcs : T.SourceManifest) ->
      \(opts : T.HaskellOpts) ->
      \(deps : List T.Dep) ->
      \(tc : P.HaskellToolchain) ->
        let outName = nameToText name
        let optLevel = optLevelFlag opts.optLevel
        let warnings = spaceSep (map T.WarningFlag Text warningFlagToText opts.warnings)
        let extensions = spaceSep (map T.Extension Text extensionToText opts.extensions)
        let ghcVersion = ghcVersionFlag opts.ghcVersion

        in { script =
''
#!/usr/bin/env bash
# Generated test script for ${outName}
# DO NOT EDIT - this file is generated from Dhall
set -euo pipefail

# Toolchain paths
GHC="${pathToText tc.ghc}"
CABAL="${pathToText tc.cabal}"

# Build and run tests
"$CABAL" test \
    ${ghcVersion} \
    --ghc-options="${optLevel} ${warnings} ${extensions}" \
    --test-show-details=direct \
    all

# Mark test as passed
echo "PASSED" > "$OUT"
''
        }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Full target build (dispatch on target kind)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Note: This would require dependent types to fully express.
-- In practice, you call the specific build function based on target kind.

in  { BuildScript
    , pathToText
    , nameToText
    , optLevelFlag
    , warningFlagToText
    , extensionToText
    , ghcVersionFlag
    , containerBaseImage
    , buildHaskell
    , buildContainer
    , buildTest
    }
