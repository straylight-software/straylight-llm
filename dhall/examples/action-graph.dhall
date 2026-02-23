-- dhall/examples/action-graph.dhall
--
-- Example: Generate the complete action graph for straylight-llm.
--
-- This shows the DICE-style incremental computation model:
-- each action has explicit inputs, outputs, and dependencies.

let T = ../Target.dhall
let A = ../Action.dhall
let gateway = ../straylight-llm.dhall

-- Build action
let buildAction = A.cabalBuild
    gateway.gateway.name
    gateway.sourceManifest
    (merge
        { Haskell = \(opts : T.HaskellOpts) -> opts
        , Container = \(_ : T.ContainerOpts) -> T.defaults.haskell
        }
        gateway.gateway.lang)

-- Test action (depends on build)
let testAction = A.cabalTest
    (T.name "straylight-llm-test")
    gateway.testManifest

-- Container build (depends on binary)
let containerAction = A.containerBuild
    (T.name "straylight-llm-container")
    (T.path "dist-newstyle/build/straylight-llm")
    T.defaults.container

-- Complete action graph
let actionGraph : A.ActionGraph =
    { name = "straylight-llm"
    , actions =
        [ buildAction
        , testAction
        , containerAction
        ]
    }

in actionGraph
