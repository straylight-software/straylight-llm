-- dhall/straylight-llm.dhall
--
-- Target definition for the straylight-llm gateway.
--
-- "The sky above the port was the color of television, tuned to a dead channel."
--                                                              — Neuromancer
--
-- This is the canonical definition of what the gateway IS:
--   - Explicit source files (no globs)
--   - Typed build options (no "-O2" strings)
--   - Declared dependencies

let T = ./Target.dhall

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Source manifest (every file explicit, no globs)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let srcDir = "gateway/src"
let appDir = "gateway/app"

let sourceManifest : T.SourceManifest =
    { files =
        [ -- App
          T.path "${appDir}/Main.hs"
          -- Core
        , T.path "${srcDir}/Api.hs"
        , T.path "${srcDir}/Config.hs"
        , T.path "${srcDir}/Handlers.hs"
        , T.path "${srcDir}/Router.hs"
        , T.path "${srcDir}/Types.hs"
          -- Coeffects (proof system)
        , T.path "${srcDir}/Coeffect/Discharge.hs"
        , T.path "${srcDir}/Coeffect/Types.hs"
          -- Effects (graded monad)
        , T.path "${srcDir}/Effects/Graded.hs"
          -- Evring (event ring / state machine abstraction)
        , T.path "${srcDir}/Evring/Event.hs"
        , T.path "${srcDir}/Evring/Handle.hs"
        , T.path "${srcDir}/Evring/Machine.hs"
        , T.path "${srcDir}/Evring/Ring.hs"
        , T.path "${srcDir}/Evring/Sigil.hs"
        , T.path "${srcDir}/Evring/Trace.hs"
          -- Providers (LLM backends)
        , T.path "${srcDir}/Provider/Anthropic.hs"
        , T.path "${srcDir}/Provider/Baseten.hs"
        , T.path "${srcDir}/Provider/ModelRegistry.hs"
        , T.path "${srcDir}/Provider/OpenRouter.hs"
        , T.path "${srcDir}/Provider/Types.hs"
        , T.path "${srcDir}/Provider/Venice.hs"
        , T.path "${srcDir}/Provider/Vertex.hs"
          -- Resilience (circuit breaker, retry, etc.)
        , T.path "${srcDir}/Resilience/Backpressure.hs"
        , T.path "${srcDir}/Resilience/Cache.hs"
        , T.path "${srcDir}/Resilience/CircuitBreaker.hs"
        , T.path "${srcDir}/Resilience/Metrics.hs"
        , T.path "${srcDir}/Resilience/Retry.hs"
          -- Security (sanitization, injection detection)
        , T.path "${srcDir}/Security/ConstantTime.hs"
        , T.path "${srcDir}/Security/ObservabilitySanitization.hs"
        , T.path "${srcDir}/Security/PromptInjection.hs"
        , T.path "${srcDir}/Security/RequestLimits.hs"
        , T.path "${srcDir}/Security/RequestSanitization.hs"
        , T.path "${srcDir}/Security/ResponseSanitization.hs"
          -- Slide (wire protocol)
        , T.path "${srcDir}/Slide/Parse.hs"
        , T.path "${srcDir}/Slide/Wire/Types.hs"
        , T.path "${srcDir}/Slide/Wire/Varint.hs"
          -- Streaming (SSE events)
        , T.path "${srcDir}/Streaming/Events.hs"
          -- Types
        , T.path "${srcDir}/Types/Anthropic.hs"
        ]
    , modules =
        [ -- Core modules
          "Api"
        , "Config"
        , "Handlers"
        , "Router"
        , "Types"
          -- Coeffects
        , "Coeffect.Discharge"
        , "Coeffect.Types"
          -- Effects
        , "Effects.Graded"
          -- Evring
        , "Evring.Event"
        , "Evring.Handle"
        , "Evring.Machine"
        , "Evring.Ring"
        , "Evring.Sigil"
        , "Evring.Trace"
          -- Providers
        , "Provider.Anthropic"
        , "Provider.Baseten"
        , "Provider.ModelRegistry"
        , "Provider.OpenRouter"
        , "Provider.Types"
        , "Provider.Venice"
        , "Provider.Vertex"
          -- Resilience
        , "Resilience.Backpressure"
        , "Resilience.Cache"
        , "Resilience.CircuitBreaker"
        , "Resilience.Metrics"
        , "Resilience.Retry"
          -- Security
        , "Security.ConstantTime"
        , "Security.ObservabilitySanitization"
        , "Security.PromptInjection"
        , "Security.RequestLimits"
        , "Security.RequestSanitization"
        , "Security.ResponseSanitization"
          -- Slide
        , "Slide.Parse"
        , "Slide.Wire.Types"
        , "Slide.Wire.Varint"
          -- Streaming
        , "Streaming.Events"
          -- Types
        , "Types.Anthropic"
        ]
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Build options (typed, not strings)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let haskellOpts : T.HaskellOpts =
    T.defaults.haskell
        -- Override specific options
        // { ghcVersion = T.GhcVersion.GHC912
           , optLevel = T.OptLevel.O2
           , warnings =
               [ T.WarningFlag.Wall
               , T.WarningFlag.Wcompat
               , T.WarningFlag.Werror
               ]
           , extensions =
               [ T.Extension.OverloadedStrings
               , T.Extension.RecordWildCards
               , T.Extension.StrictData
               , T.Extension.DataKinds
               , T.Extension.TypeOperators
               , T.Extension.DeriveGeneric
               , T.Extension.DerivingStrategies
               , T.Extension.LambdaCase
               , T.Extension.BangPatterns
               , T.Extension.NamedFieldPuns
               ]
           , threaded = True
           , rtsopts = True
           }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Dependencies (explicit, typed)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let dependencies : List T.Dep =
    [ -- Core
      T.Dep.Nix (T.nixpkgs "haskellPackages.aeson")
    , T.Dep.Nix (T.nixpkgs "haskellPackages.bytestring")
    , T.Dep.Nix (T.nixpkgs "haskellPackages.containers")
    , T.Dep.Nix (T.nixpkgs "haskellPackages.text")
    , T.Dep.Nix (T.nixpkgs "haskellPackages.time")
      -- HTTP
    , T.Dep.Nix (T.nixpkgs "haskellPackages.http-client")
    , T.Dep.Nix (T.nixpkgs "haskellPackages.http-client-tls")
    , T.Dep.Nix (T.nixpkgs "haskellPackages.http-types")
    , T.Dep.Nix (T.nixpkgs "haskellPackages.wai")
    , T.Dep.Nix (T.nixpkgs "haskellPackages.warp")
      -- Servant
    , T.Dep.Nix (T.nixpkgs "haskellPackages.servant")
    , T.Dep.Nix (T.nixpkgs "haskellPackages.servant-server")
      -- Crypto (for discharge proofs)
    , T.Dep.Nix (T.nixpkgs "haskellPackages.cryptonite")
    , T.Dep.Nix (T.nixpkgs "haskellPackages.memory")
      -- UUID
    , T.Dep.Nix (T.nixpkgs "haskellPackages.uuid")
    ]

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Targets
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- The main gateway binary
let gateway : T.Target =
    { name = T.name "straylight-llm"
    , kind = T.TargetKind.Binary
    , lang = T.Lang.Haskell haskellOpts
    , srcs = sourceManifest
    , deps = dependencies
    }

-- Container image (scratch base for minimal size)
let containerOpts : T.ContainerOpts =
    { base = T.ContainerBase.Scratch
    , exposedPorts = [ 8080 ]
    , user = "nonroot"
    , workdir = T.path "/app"
    }

let container : T.Target =
    { name = T.name "straylight-llm-container"
    , kind = T.TargetKind.Container
    , lang = T.Lang.Container containerOpts
    , srcs = { files = [] : List T.Path, modules = [] : List Text }
    , deps = [ T.Dep.Local (T.label "straylight-llm") ]
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Test target
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let testDir = "gateway/test"

let testManifest : T.SourceManifest =
    { files =
        [ T.path "${testDir}/Main.hs"
        , T.path "${testDir}/Property/Generators.hs"
        , T.path "${testDir}/Property/TypesProps.hs"
        , T.path "${testDir}/Property/CoeffectProps.hs"
        , T.path "${testDir}/Property/StreamingProps.hs"
        , T.path "${testDir}/Integration/LifecycleTests.hs"
        , T.path "${testDir}/Integration/ProofTests.hs"
        , T.path "${testDir}/Formal/ProofCorrespondence.hs"
        ]
    , modules =
        [ "Main"
        , "Property.Generators"
        , "Property.TypesProps"
        , "Property.CoeffectProps"
        , "Property.StreamingProps"
        , "Integration.LifecycleTests"
        , "Integration.ProofTests"
        , "Formal.ProofCorrespondence"
        ]
    }

let tests : T.Target =
    { name = T.name "straylight-llm-test"
    , kind = T.TargetKind.Test
    , lang = T.Lang.Haskell haskellOpts
    , srcs = testManifest
    , deps =
        dependencies
        # [ T.Dep.Nix (T.nixpkgs "haskellPackages.hedgehog")
          , T.Dep.Nix (T.nixpkgs "haskellPackages.tasty")
          , T.Dep.Nix (T.nixpkgs "haskellPackages.tasty-hedgehog")
          , T.Dep.Local (T.label "straylight-llm")
          ]
    }

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Exports
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

in  { -- Targets
      gateway
    , container
    , tests
      -- For inspection
    , sourceManifest
    , testManifest
    , haskellOpts
    , dependencies
    }
