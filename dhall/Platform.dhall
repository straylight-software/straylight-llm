-- dhall/Platform.dhall
--
-- Platform and toolchain configuration for straylight-llm.
-- Adapted from aleph cube architecture.
--
-- All paths come from Nix store - no hardcoded /usr/bin paths.

let T = ./Target.dhall

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Platform
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let Cpu = < X86_64 | Aarch64 >
let Os = < Linux | Darwin >

let Platform = { cpu : Cpu, os : Os }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Haskell toolchain (from Nix)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let HaskellToolchain =
    { ghc : T.Path
    , ghcPkg : T.Path
    , cabal : T.Path
    , haddock : T.Path
    -- Package database from nix
    , packageDb : T.Path
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Container toolchain
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let ContainerToolchain =
    { -- Nix container builders
      dockerTools : T.Path
      -- OCI runtime (for local testing)
    , podman : Optional T.Path
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Lean toolchain (for proofs)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let LeanToolchain =
    { lean : T.Path
    , lake : T.Path
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Combined toolchain
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let Toolchain =
    { haskell : HaskellToolchain
    , container : ContainerToolchain
    , lean : Optional LeanToolchain
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Nix-based toolchain resolution
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Given a GHC version, produce the Nix attribute path
let ghcVersionToNixAttr : T.GhcVersion -> Text = \(v : T.GhcVersion) ->
    merge
        { GHC948 = "haskell.compiler.ghc948"
        , GHC9101 = "haskell.compiler.ghc9101"
        , GHC9103 = "haskell.compiler.ghc9103"
        , GHC912 = "haskell.compiler.ghc912"
        }
        v

-- Generate flake reference for GHC
let ghcFlakeRef : T.GhcVersion -> T.FlakeRef = \(v : T.GhcVersion) ->
    { flake = "nixpkgs", attr = ghcVersionToNixAttr v }

in  { -- Platform types
      Cpu, Os, Platform
      -- Toolchain types
    , HaskellToolchain
    , ContainerToolchain
    , LeanToolchain
    , Toolchain
      -- Nix helpers
    , ghcVersionToNixAttr
    , ghcFlakeRef
    }
