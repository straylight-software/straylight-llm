-- dhall/examples/generate-build.dhall
--
-- Example: Generate a build script for the gateway.
--
-- Usage:
--   dhall text < examples/generate-build.dhall > build.sh
--   chmod +x build.sh
--   ./build.sh

let T = ../Target.dhall
let P = ../Platform.dhall
let B = ../Build.dhall
let gateway = ../straylight-llm.dhall

-- Define the toolchain (paths from nix develop)
let toolchain : P.HaskellToolchain =
    { ghc = T.path "ghc"
    , ghcPkg = T.path "ghc-pkg"
    , cabal = T.path "cabal"
    , haddock = T.path "haddock"
    , packageDb = T.path "$GHC_PACKAGE_PATH"
    }

-- Extract Haskell options from the gateway target
let haskellOpts : T.HaskellOpts =
    merge
        { Haskell = \(opts : T.HaskellOpts) -> opts
        , Container = \(_ : T.ContainerOpts) -> T.defaults.haskell
        }
        gateway.gateway.lang

-- Generate the build script
let script = B.buildHaskell
    gateway.gateway.name
    gateway.sourceManifest
    haskellOpts
    gateway.dependencies
    toolchain

in script.script
