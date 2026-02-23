-- dhall/Target.dhall
--
-- Build target types for straylight-llm gateway.
-- Adapted from aleph cube architecture.
--
-- Key principle: No strings for semantic values. Real types.
-- "Every file is explicit. Every flag is typed."
--                                    — Continuity.lean

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Primitives (not raw Text)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let Path = { _path : Text }
let path : Text -> Path = \(t : Text) -> { _path = t }

let Name = { _name : Text }
let name : Text -> Name = \(t : Text) -> { _name = t }

let Label = { package : Optional Text, name : Text }
let label : Text -> Label = \(n : Text) -> { package = None Text, name = n }

let FlakeRef = { flake : Text, attr : Text }
let nixpkgs : Text -> FlakeRef = \(a : Text) -> { flake = "nixpkgs", attr = a }

let Dep = < Local : Label | Nix : FlakeRef >

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Haskell-specific types
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- GHC version (typed, not "9.10.3" string)
let GhcVersion = < GHC948 | GHC9101 | GHC9103 | GHC912 >

-- Optimization level (typed, not "-O2" string)
let OptLevel = < O0 | O1 | O2 >

-- Warning flags (typed, not "-Wall" string)
let WarningFlag =
    < Wall
    | Wcompat
    | Werror
    | Wno_unused_imports
    | Wno_name_shadowing
    >

-- Extension (typed, not "OverloadedStrings" string)
let Extension =
    < OverloadedStrings
    | RecordWildCards
    | StrictData
    | DataKinds
    | TypeOperators
    | DeriveGeneric
    | DerivingStrategies
    | LambdaCase
    | BangPatterns
    | NamedFieldPuns
    | GHC2021
    >

-- Haskell build options
let HaskellOpts =
    { ghcVersion : GhcVersion
    , optLevel : OptLevel
    , warnings : List WarningFlag
    , extensions : List Extension
    , threaded : Bool
    , rtsopts : Bool
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Container types
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Container base image
let ContainerBase = < Scratch | Alpine | Distroless >

-- Container options
let ContainerOpts =
    { base : ContainerBase
    , exposedPorts : List Natural
    , user : Text
    , workdir : Path
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Target kinds
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let TargetKind =
    < Binary      -- Executable
    | Library     -- Haskell library
    | Test        -- Test suite
    | Container   -- OCI container image
    >

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Language union
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let Lang =
    < Haskell : HaskellOpts
    | Container : ContainerOpts
    >

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Source manifest (explicit, no globs)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let SourceManifest =
    { -- Every source file is explicitly listed (no globs)
      files : List Path
      -- Module hierarchy
    , modules : List Text
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Unified target
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let Target =
    { name : Name
    , kind : TargetKind
    , lang : Lang
    , srcs : SourceManifest
    , deps : List Dep
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Defaults
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let defaults =
    { haskell =
        { ghcVersion = GhcVersion.GHC9103
        , optLevel = OptLevel.O2
        , warnings = [ WarningFlag.Wall, WarningFlag.Wcompat, WarningFlag.Werror ]
        , extensions =
            [ Extension.OverloadedStrings
            , Extension.RecordWildCards
            , Extension.StrictData
            , Extension.DataKinds
            , Extension.TypeOperators
            , Extension.DeriveGeneric
            , Extension.DerivingStrategies
            , Extension.LambdaCase
            , Extension.BangPatterns
            , Extension.NamedFieldPuns
            ]
        , threaded = True
        , rtsopts = True
        }
    , container =
        { base = ContainerBase.Scratch
        , exposedPorts = [ 8080 ]
        , user = "nonroot"
        , workdir = path "/app"
        }
    }

in  { -- Primitives
      Path, path
    , Name, name
    , Label, label
    , FlakeRef, nixpkgs
    , Dep
      -- Haskell types
    , GhcVersion, OptLevel, WarningFlag, Extension, HaskellOpts
      -- Container types
    , ContainerBase, ContainerOpts
      -- Target types
    , TargetKind, Lang, SourceManifest, Target
      -- Defaults
    , defaults
    }
