{- Provider.dhall

   Provider configuration for the straylight-llm gateway.
   
   Each provider has:
   - Base URL
   - API key source (file path or environment variable)
   - Enable/disable flag
   - Optional Vertex-specific config
-}

let Resource = ../../aleph-reference/dhall/Resource.dhall

--------------------------------------------------------------------------------
-- Vertex AI Configuration
--
-- Google Cloud's Vertex AI requires OAuth and project configuration.
-- Uses Application Default Credentials (ADC) or service account key.
--------------------------------------------------------------------------------

let VertexConfig
    : Type
    = { projectId : Text
      , location : Text                  -- e.g., "us-central1"
      , serviceAccountKeyPath : Optional Text
      }

let defaultVertex : VertexConfig =
      { projectId = ""
      , location = "us-central1"
      , serviceAccountKeyPath = None Text
      }

--------------------------------------------------------------------------------
-- API Key Source
--
-- Where to get the API key. In priority order:
-- 1. Direct value (for testing only, never commit!)
-- 2. File path
-- 3. Environment variable
--------------------------------------------------------------------------------

let KeySource
    : Type
    = < Direct : Text
      | File : Text
      | Env : Text
      >

--------------------------------------------------------------------------------
-- Provider Configuration
--------------------------------------------------------------------------------

let Provider
    : Type
    = { name : Text
      , enabled : Bool
      , baseUrl : Text
      , keySource : Optional KeySource
      , vertexConfig : Optional VertexConfig
      , coeffects : Resource.Resources     -- What this provider requires
      }

-- Provider constructors

let venice
    : Optional KeySource -> Provider
    = \(key : Optional KeySource) ->
        { name = "venice"
        , enabled = True
        , baseUrl = "https://api.venice.ai/api/v1"
        , keySource = key
        , vertexConfig = None VertexConfig
        , coeffects = Resource.combine Resource.network (Resource.auth "venice")
        }

let vertex
    : VertexConfig -> Provider
    = \(cfg : VertexConfig) ->
        { name = "vertex"
        , enabled = cfg.projectId != ""
        , baseUrl = ""  -- Constructed from project/location at runtime
        , keySource = None KeySource
        , vertexConfig = Some cfg
        , coeffects = Resource.combine Resource.network (Resource.auth "google-cloud")
        }

let baseten
    : Optional KeySource -> Provider
    = \(key : Optional KeySource) ->
        { name = "baseten"
        , enabled = True
        , baseUrl = "https://inference.baseten.co/v1"
        , keySource = key
        , vertexConfig = None VertexConfig
        , coeffects = Resource.combine Resource.network (Resource.auth "baseten")
        }

let openrouter
    : Optional KeySource -> Provider
    = \(key : Optional KeySource) ->
        { name = "openrouter"
        , enabled = True
        , baseUrl = "https://openrouter.ai/api/v1"
        , keySource = key
        , vertexConfig = None VertexConfig
        , coeffects = Resource.combine Resource.network (Resource.auth "openrouter")
        }

-- Disabled provider (placeholder)
let disabled
    : Text -> Provider
    = \(name : Text) ->
        { name = name
        , enabled = False
        , baseUrl = ""
        , keySource = None KeySource
        , vertexConfig = None VertexConfig
        , coeffects = Resource.pure
        }

in  { -- Types
      VertexConfig
    , KeySource
    , Provider
      -- Defaults
    , defaultVertex
      -- Constructors
    , venice
    , vertex
    , baseten
    , openrouter
    , disabled
    }
