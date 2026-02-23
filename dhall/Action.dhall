-- dhall/Action.dhall
--
-- DICE-style incremental computation actions.
--
-- Based on Meta's DICE (Dynamic Incremental Caching Engine) from Buck2.
-- Key concepts:
--   - Actions have typed inputs and outputs
--   - Results are cached based on input hash
--   - Dependencies are explicit (no implicit filesystem access)
--
-- "The computation engine will output values corresponding to given Keys,
--  reusing previously computed values when possible."
--                                                      — DICE lib.rs

let T = ./Target.dhall

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Action primitives
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Hash of inputs (for cache key)
let Hash = { _hash : Text }

-- Action identifier
let ActionId = { category : Text, identifier : Text }

-- Action output kinds
let OutputKind =
    < File : T.Path          -- Single file output
    | Directory : T.Path     -- Directory output
    | Value : Text           -- In-memory value (serialized)
    | Void                   -- No output (side effect only)
    >

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Action definition
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- A DICE action with typed inputs/outputs
let Action =
    { id : ActionId
      -- Explicit file inputs (hashed for cache key)
    , inputs : List T.Path
      -- Explicit action dependencies (other actions that must run first)
    , deps : List ActionId
      -- Output specification
    , output : OutputKind
      -- Command to execute
    , command : Text
      -- Environment variables (explicit, no implicit env access)
    , env : List { key : Text, value : Text }
      -- Whether action is cacheable
    , cacheable : Bool
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Haskell-specific actions
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Compile a Haskell module
let compileModule
    : T.Name -> T.Path -> T.HaskellOpts -> List T.Path -> Action
    = \(name : T.Name) ->
      \(src : T.Path) ->
      \(opts : T.HaskellOpts) ->
      \(deps : List T.Path) ->
        { id = { category = "haskell", identifier = "compile:${name._name}" }
        , inputs = [ src ] # deps
        , deps = [] : List ActionId
        , output = OutputKind.File (T.path "dist-newstyle/${name._name}.o")
        , command =
            ''
            ghc -c ${src._path} -o $OUT
            ''
        , env = [] : List { key : Text, value : Text }
        , cacheable = True
        }

-- Link a Haskell binary
let linkBinary
    : T.Name -> List T.Path -> T.HaskellOpts -> Action
    = \(name : T.Name) ->
      \(objects : List T.Path) ->
      \(opts : T.HaskellOpts) ->
        let Prelude = https://prelude.dhall-lang.org/v23.0.0/package.dhall
        let objectFiles = Prelude.Text.concatMapSep " " T.Path (\(p : T.Path) -> p._path) objects
        in
        { id = { category = "haskell", identifier = "link:${name._name}" }
        , inputs = objects
        , deps = [] : List ActionId
        , output = OutputKind.File (T.path "dist-newstyle/${name._name}")
        , command =
            ''
            ghc -o $OUT ${objectFiles}
            ''
        , env = [] : List { key : Text, value : Text }
        , cacheable = True
        }

-- Run cabal build (higher-level action)
let cabalBuild
    : T.Name -> T.SourceManifest -> T.HaskellOpts -> Action
    = \(name : T.Name) ->
      \(srcs : T.SourceManifest) ->
      \(opts : T.HaskellOpts) ->
        { id = { category = "cabal", identifier = "build:${name._name}" }
        , inputs = srcs.files
        , deps = [] : List ActionId
        , output = OutputKind.File (T.path "dist-newstyle/build/${name._name}")
        , command =
            ''
            cabal build ${name._name}
            ''
        , env = [] : List { key : Text, value : Text }
        , cacheable = True
        }

-- Run cabal test
let cabalTest
    : T.Name -> T.SourceManifest -> Action
    = \(name : T.Name) ->
      \(srcs : T.SourceManifest) ->
        { id = { category = "cabal", identifier = "test:${name._name}" }
        , inputs = srcs.files
        , deps = [ { category = "cabal", identifier = "build:${name._name}" } ]
        , output = OutputKind.Value "test-result"
        , command =
            ''
            cabal test ${name._name} --test-show-details=direct
            ''
        , env = [] : List { key : Text, value : Text }
        , cacheable = False  -- Tests should always run
        }

-- Build container image
let containerBuild
    : T.Name -> T.Path -> T.ContainerOpts -> Action
    = \(name : T.Name) ->
      \(binary : T.Path) ->
      \(opts : T.ContainerOpts) ->
        { id = { category = "container", identifier = "build:${name._name}" }
        , inputs = [ binary ]
        , deps = [] : List ActionId
        , output = OutputKind.File (T.path "result")
        , command =
            ''
            nix build .#${name._name}
            ''
        , env = [] : List { key : Text, value : Text }
        , cacheable = True
        }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Lean proof actions (for verification)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let leanBuild
    : T.Name -> List T.Path -> Action
    = \(name : T.Name) ->
      \(srcs : List T.Path) ->
        { id = { category = "lean", identifier = "build:${name._name}" }
        , inputs = srcs
        , deps = [] : List ActionId
        , output = OutputKind.Directory (T.path ".lake/build")
        , command =
            ''
            lake build
            ''
        , env = [] : List { key : Text, value : Text }
        , cacheable = True
        }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Action graph
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- A complete build graph
let ActionGraph =
    { name : Text
    , actions : List Action
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Exports
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

in  { -- Types
      Hash
    , ActionId
    , OutputKind
    , Action
    , ActionGraph
      -- Haskell actions
    , compileModule
    , linkBinary
    , cabalBuild
    , cabalTest
    , containerBuild
      -- Lean actions
    , leanBuild
    }
