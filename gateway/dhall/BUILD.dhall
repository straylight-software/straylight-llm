{- BUILD.dhall

   Build manifest for straylight-llm gateway.
   
   This defines:
   1. What sources comprise the build
   2. What coeffects (external resources) are required
   3. What toolchain to use
   
   The manifest is used by:
   - Nix: to construct the derivation
   - CI: to validate hermetic builds
   - DICE: to construct the action graph
-}

let Build = ../../aleph-reference/dhall/Build.dhall
let Resource = ../../aleph-reference/dhall/Resource.dhall
let Toolchain = ../../aleph-reference/dhall/Toolchain.dhall

--------------------------------------------------------------------------------
-- Gateway Package Metadata
--------------------------------------------------------------------------------

let Package =
      { name = "straylight-llm"
      , version = "0.1.0.0"
      , synopsis = "CGP-first OpenAI-compatible LLM gateway"
      , license = "BSD-3-Clause"
      , author = "Straylight Software"
      , maintainer = "dev@straylight.ai"
      }

--------------------------------------------------------------------------------
-- Source Files
--------------------------------------------------------------------------------

let sources = Build.Src.Files
      [ "src/Main.hs"
      , "src/Config.hs"
      , "src/Types.hs"
      , "src/Router.hs"
      , "src/Api.hs"
      , "src/Handlers.hs"
      , "src/Provider/OpenRouter.hs"
      , "src/Provider/Venice.hs"
      , "src/Provider/Vertex.hs"
      , "src/Provider/Baseten.hs"
      , "src/Effects/Graded.hs"
      , "src/Coeffect/Types.hs"
      , "src/Coeffect/Discharge.hs"
      ]

let testSources = Build.Src.Files
      [ "test/Main.hs"
      , "test/Property/Generators.hs"
      , "test/Property/TypesProps.hs"
      , "test/Property/CoeffectProps.hs"
      ]

--------------------------------------------------------------------------------
-- Dependencies
--------------------------------------------------------------------------------

let deps =
      [ Build.dep.flake "nixpkgs#haskell.packages.ghc912.ghc"
        -- Core
      , Build.dep.pkgconfig "zlib"
        -- Haskell packages
      , Build.dep.local "base"
      , Build.dep.local "text"
      , Build.dep.local "bytestring"
      , Build.dep.local "aeson"
      , Build.dep.local "servant"
      , Build.dep.local "servant-server"
      , Build.dep.local "warp"
      , Build.dep.local "http-client"
      , Build.dep.local "http-client-tls"
      , Build.dep.local "http-types"
      , Build.dep.local "mtl"
      , Build.dep.local "containers"
      , Build.dep.local "crypton"
      , Build.dep.local "memory"
      , Build.dep.local "uuid"
      , Build.dep.local "time"
      , Build.dep.local "base16-bytestring"
      ]

let testDeps =
      [ Build.dep.local "hedgehog"
      , Build.dep.local "tasty"
      , Build.dep.local "tasty-hedgehog"
      ]

--------------------------------------------------------------------------------
-- Build Coeffects
--
-- What external resources does the build require?
-- Pure builds require nothing external (ideal for reproducibility).
-- Network builds fetch dependencies (less hermetic).
--------------------------------------------------------------------------------

let buildCoeffects : Resource.Resources =
      -- Gateway builds are pure (all deps are nix flake refs)
      -- No network access during build, only at graph construction
      Resource.pure

let runtimeCoeffects : Resource.Resources =
      -- At runtime, the gateway needs network and auth
      Resource.combine
        Resource.network
        ( Resource.combine
            (Resource.auth "openrouter")
            ( Resource.combine
                (Resource.auth "venice")
                ( Resource.combine
                    (Resource.auth "baseten")
                    (Resource.auth "google-cloud")
                )
            )
        )

--------------------------------------------------------------------------------
-- Toolchain
--
-- GHC 9.12 with standard Haskell toolchain
--------------------------------------------------------------------------------

let haskellToolchain : Toolchain.Toolchain =
      { compiler = Toolchain.Compiler.GHC { version = "9.12" }
      , host = { arch = "x86_64", os = "linux", abi = "gnu" }
      , target = { arch = "x86_64", os = "linux", abi = "gnu" }
      , cflags = [] : List Text
      , cxxflags = [] : List Text
      , ldflags = [] : List Text
      , sysroot = None Text
      }

--------------------------------------------------------------------------------
-- Build Targets
--------------------------------------------------------------------------------

let gatewayLib : Build.Target =
      { name = "straylight-llm-lib"
      , srcs = sources
      , deps = deps
      , toolchain = haskellToolchain
      , requires = buildCoeffects
      }

let gatewayBinary : Build.Target =
      { name = "straylight-llm"
      , srcs = Build.Src.Files [ "app/Main.hs" ]
      , deps = [ Build.dep.local ":straylight-llm-lib" ] # deps
      , toolchain = haskellToolchain
      , requires = buildCoeffects
      }

let tests : Build.Target =
      { name = "straylight-llm-test"
      , srcs = testSources
      , deps = [ Build.dep.local ":straylight-llm-lib" ] # deps # testDeps
      , toolchain = haskellToolchain
      , requires = buildCoeffects
      }

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

in  { -- Package metadata
      package = Package
      
      -- Build targets
    , targets =
        [ gatewayLib
        , gatewayBinary
        , tests
        ]
      
      -- Coeffects
    , buildCoeffects = buildCoeffects
    , runtimeCoeffects = runtimeCoeffects
      
      -- Re-exports for customization
    , Resource = Resource
    , Build = Build
    , Toolchain = Toolchain
    }
