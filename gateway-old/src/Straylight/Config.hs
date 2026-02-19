{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                       // straylight // config
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   "He'd operated on an almost permanent adrenaline high, a
    byproduct of youth and proficiency, jacked into a custom
    cyberspace deck that projected his disembodied consciousness
    into the consensual hallucination that was the matrix."

                                                               — Neuromancer

   Gateway configuration with CGP-first routing settings.
   n.b. corresponds to Lean4 Straylight.Provider configs.
-}
module Straylight.Config
  ( -- // configuration // types
    Config (..)
  , CgpConfig (..)
  , OpenRouterConfig (..)
  , LogLevel (..)
    -- // loading // functions
  , loadConfig
  , defaultConfig
    -- // query // functions
  , cgpEnabled
  , openRouterEnabled
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (lookupEnv)
import Text.Read (readMaybe)


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // log // level
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Logging level for the gateway process
data LogLevel
  = LogCritical
  | LogDebug
  | LogError
  | LogInfo
  | LogWarning
  deriving stock (Eq, Show, Ord)


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // cgp // config
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | CGP (Cloud GPU Provider) configuration.
--   n.b. primary backend — requests route here first
data CgpConfig = CgpConfig
  { cgpApiBase        :: !Text
    -- ^ Base URL of the CGP inference endpoint.
    --   n.b. do NOT include /v1 suffix
  , cgpApiKey         :: !(Maybe Text)
    -- ^ API key for the CGP endpoint (optional)
  , cgpApiKeyFile     :: !(Maybe FilePath)
    -- ^ Path to file containing API key
  , cgpTimeout        :: !Int
    -- ^ Timeout in seconds for CGP requests
  , cgpConnectTimeout :: !Int
    -- ^ Connection timeout in seconds
  , cgpHealthEndpoint :: !Text
    -- ^ Health check endpoint path
  , cgpModels         :: ![(Text, Text)]
    -- ^ Model mappings: client model → backend model
  }
  deriving stock (Eq, Show)


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // openrouter // config
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | OpenRouter fallback configuration.
--   cf. https://openrouter.ai/docs
data OpenRouterConfig = OpenRouterConfig
  { orApiBase      :: !Text
    -- ^ Base URL (default: https://openrouter.ai/api)
  , orApiKey       :: !(Maybe Text)
    -- ^ API key for OpenRouter
  , orApiKeyFile   :: !(Maybe FilePath)
    -- ^ Path to file containing API key
  , orTimeout      :: !Int
    -- ^ Timeout in seconds
  , orDefaultModel :: !(Maybe Text)
    -- ^ Default model if none specified
  , orSiteName     :: !Text
    -- ^ Site name for OpenRouter headers
  , orSiteUrl      :: !(Maybe Text)
    -- ^ Site URL for OpenRouter headers
  , orModels       :: ![(Text, Text)]
    -- ^ Model mappings
  }
  deriving stock (Eq, Show)


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // gateway // config
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Main gateway configuration
data Config = Config
  { cfgPort       :: !Int
    -- ^ TCP port the gateway listens on
  , cfgHost       :: !Text
    -- ^ IP address to bind to
  , cfgLogLevel   :: !LogLevel
    -- ^ Logging level
  , cfgCgp        :: !CgpConfig
    -- ^ CGP backend configuration
  , cfgOpenRouter :: !OpenRouterConfig
    -- ^ OpenRouter fallback configuration
  }
  deriving stock (Eq, Show)


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // defaults // config
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Default CGP configuration (disabled)
defaultCgpConfig :: CgpConfig
defaultCgpConfig = CgpConfig
  { cgpApiBase        = ""
  , cgpApiKey         = Nothing
  , cgpApiKeyFile     = Nothing
  , cgpTimeout        = 120
  , cgpConnectTimeout = 5
  , cgpHealthEndpoint = "/health"
  , cgpModels         = []
  }

-- | Default OpenRouter configuration
defaultOpenRouterConfig :: OpenRouterConfig
defaultOpenRouterConfig = OpenRouterConfig
  { orApiBase      = "https://openrouter.ai/api"
  , orApiKey       = Nothing
  , orApiKeyFile   = Nothing
  , orTimeout      = 120
  , orDefaultModel = Nothing
  , orSiteName     = "straylight-llm"
  , orSiteUrl      = Nothing
  , orModels       = []
  }

-- | Default gateway configuration
defaultConfig :: Config
defaultConfig = Config
  { cfgPort       = 4000
  , cfgHost       = "0.0.0.0"
  , cfgLogLevel   = LogInfo
  , cfgCgp        = defaultCgpConfig
  , cfgOpenRouter = defaultOpenRouterConfig
  }


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // loading // config
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Load configuration from environment variables.
--   n.b. environment takes precedence over defaults
loadConfig :: IO Config
loadConfig = do
  -- Gateway settings
  port     <- envInt "STRAYLIGHT_PORT" 4000
  host     <- envText "STRAYLIGHT_HOST" "0.0.0.0"
  logLevel <- envLogLevel "STRAYLIGHT_LOG_LEVEL" LogInfo

  -- CGP settings
  cgpApiBase        <- envText "CGP_API_BASE" ""
  cgpApiKey         <- envMaybeText "CGP_API_KEY"
  cgpApiKeyFile     <- envMaybeString "CGP_API_KEY_FILE"
  cgpTimeout        <- envInt "CGP_TIMEOUT" 120
  cgpConnectTimeout <- envInt "CGP_CONNECT_TIMEOUT" 5

  -- OpenRouter settings
  orApiBase  <- envText "OPENROUTER_API_BASE" "https://openrouter.ai/api"
  orApiKey   <- envMaybeText "OPENROUTER_API_KEY"
  orApiKeyFile <- envMaybeString "OPENROUTER_API_KEY_FILE"
  orTimeout  <- envInt "OPENROUTER_TIMEOUT" 120

  pure Config
    { cfgPort     = port
    , cfgHost     = host
    , cfgLogLevel = logLevel
    , cfgCgp = CgpConfig
        { cgpApiBase        = cgpApiBase
        , cgpApiKey         = cgpApiKey
        , cgpApiKeyFile     = cgpApiKeyFile
        , cgpTimeout        = cgpTimeout
        , cgpConnectTimeout = cgpConnectTimeout
        , cgpHealthEndpoint = "/health"
        , cgpModels         = []
        }
    , cfgOpenRouter = OpenRouterConfig
        { orApiBase      = orApiBase
        , orApiKey       = orApiKey
        , orApiKeyFile   = orApiKeyFile
        , orTimeout      = orTimeout
        , orDefaultModel = Nothing
        , orSiteName     = "straylight-llm"
        , orSiteUrl      = Nothing
        , orModels       = []
        }
    }


{- ────────────────────────────────────────────────────────────────────────────────
                                                        // env // helpers
   ──────────────────────────────────────────────────────────────────────────────── -}

envInt :: String -> Int -> IO Int
envInt name def = do
  mVal <- lookupEnv name
  pure $ fromMaybe def (mVal >>= readMaybe)

envText :: String -> Text -> IO Text
envText name def = do
  mVal <- lookupEnv name
  pure $ maybe def T.pack mVal

envMaybeText :: String -> IO (Maybe Text)
envMaybeText name = do
  mVal <- lookupEnv name
  pure $ T.pack <$> mVal

envMaybeString :: String -> IO (Maybe String)
envMaybeString = lookupEnv

envLogLevel :: String -> LogLevel -> IO LogLevel
envLogLevel name def = do
  mVal <- lookupEnv name
  pure $ case mVal of
    Just "debug"    -> LogDebug
    Just "info"     -> LogInfo
    Just "warning"  -> LogWarning
    Just "error"    -> LogError
    Just "critical" -> LogCritical
    _               -> def


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // query // functions
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Check if CGP is enabled (has non-empty apiBase)
cgpEnabled :: Config -> Bool
cgpEnabled cfg = not $ T.null $ cgpApiBase $ cfgCgp cfg

-- | Check if OpenRouter is enabled (has API key)
openRouterEnabled :: Config -> Bool
openRouterEnabled cfg =
  case orApiKey (cfgOpenRouter cfg) of
    Just k  -> not $ T.null k
    Nothing -> False
