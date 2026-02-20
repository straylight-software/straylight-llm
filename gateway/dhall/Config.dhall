{- Config.dhall

   Gateway configuration schema for straylight-llm.
   
   This is the typed equivalent of Config.hs, enabling:
   1. Compile-time validation of config shape
   2. Type-safe config merging
   3. Documentation as types
   
   Usage:
     dhall resolve --file config.dhall
     dhall-to-json --file config.dhall > config.json
-}

let Provider = ./Provider.dhall
let Resource = ../../aleph-reference/dhall/Resource.dhall

--------------------------------------------------------------------------------
-- Log Level
--------------------------------------------------------------------------------

let LogLevel
    : Type
    = < Debug | Info | Warn | Error >

let renderLogLevel : LogLevel -> Text = \(l : LogLevel) ->
    merge
      { Debug = "debug"
      , Info = "info"
      , Warn = "warn"
      , Error = "error"
      }
      l

--------------------------------------------------------------------------------
-- Gateway Configuration
--------------------------------------------------------------------------------

let GatewayConfig
    : Type
    = { -- Server settings
        port : Natural
      , host : Text
      , logLevel : LogLevel
      , requestTimeout : Natural    -- seconds
      , maxRetries : Natural
        
        -- Providers (in priority order)
      , providers : List Provider.Provider
        
        -- Combined coeffects (computed from providers)
      , coeffects : Resource.Resources
      }

--------------------------------------------------------------------------------
-- Default Configuration
--------------------------------------------------------------------------------

let defaultConfig : GatewayConfig =
      let providers =
            [ Provider.venice (Some (Provider.KeySource.Env "VENICE_API_KEY"))
            , Provider.vertex Provider.defaultVertex
            , Provider.baseten (Some (Provider.KeySource.Env "BASETEN_API_KEY"))
            , Provider.openrouter (Some (Provider.KeySource.Env "OPENROUTER_API_KEY"))
            ]
      
      -- Compute combined coeffects from all enabled providers
      let allCoeffects =
            List/fold
              Provider.Provider
              providers
              Resource.Resources
              (\(p : Provider.Provider) -> \(acc : Resource.Resources) ->
                if p.enabled then Resource.combine p.coeffects acc else acc)
              Resource.pure
      
      in  { port = 8080
          , host = "0.0.0.0"
          , logLevel = LogLevel.Info
          , requestTimeout = 120
          , maxRetries = 3
          , providers = providers
          , coeffects = allCoeffects
          }

--------------------------------------------------------------------------------
-- Configuration Constructors
--------------------------------------------------------------------------------

-- Create config with specific providers
let withProviders
    : List Provider.Provider -> GatewayConfig -> GatewayConfig
    = \(providers : List Provider.Provider) ->
      \(cfg : GatewayConfig) ->
        cfg // { providers = providers }

-- Override port
let withPort
    : Natural -> GatewayConfig -> GatewayConfig
    = \(port : Natural) ->
      \(cfg : GatewayConfig) ->
        cfg // { port = port }

-- Override log level
let withLogLevel
    : LogLevel -> GatewayConfig -> GatewayConfig
    = \(level : LogLevel) ->
      \(cfg : GatewayConfig) ->
        cfg // { logLevel = level }

-- Production config (stricter timeouts, less verbose logging)
let productionConfig : GatewayConfig =
      defaultConfig
        // { logLevel = LogLevel.Warn
           , requestTimeout = 60
           , maxRetries = 2
           }

-- Development config (verbose logging, longer timeouts)
let developmentConfig : GatewayConfig =
      defaultConfig
        // { logLevel = LogLevel.Debug
           , requestTimeout = 300
           , maxRetries = 5
           }

in  { -- Types
      LogLevel
    , GatewayConfig
    , Provider = Provider
    , Resource = Resource
      -- Rendering
    , renderLogLevel
      -- Defaults
    , defaultConfig
    , productionConfig
    , developmentConfig
      -- Modifiers
    , withProviders
    , withPort
    , withLogLevel
    }
