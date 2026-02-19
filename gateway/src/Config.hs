-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                              // straylight-llm // config
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Case had seen it all. This was old, done."
--
--                                                              — Neuromancer
--
-- Configuration for the LLM gateway proxy. Reads provider credentials from
-- file paths (never hardcoded), supports environment variable overrides.
--
-- Provider priority: Venice -> Vertex -> Baseten -> OpenAI
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Config
    ( -- * Configuration
      Config (..)
    , ProviderConfig (..)
    , VertexConfig (..)

      -- * Loading
    , loadConfig
    , loadConfigFromEnv

      -- * Defaults
    , defaultConfig
    ) where

import Control.Exception (IOException, try)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Text.Read (readMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Environment (lookupEnv)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Vertex AI requires OAuth and project configuration
data VertexConfig = VertexConfig
    { vcProjectId :: Text
    , vcLocation :: Text             -- e.g., "us-central1"
    , vcServiceAccountKeyPath :: Maybe FilePath
    -- ^ Path to service account JSON key. If Nothing, uses ADC
    -- (Application Default Credentials from gcloud auth)
    }
    deriving (Eq, Show)

-- | Configuration for a single provider
data ProviderConfig = ProviderConfig
    { pcEnabled :: Bool
    , pcBaseUrl :: Text
    , pcApiKeyPath :: Maybe FilePath  -- Path to file containing API key
    , pcApiKey :: Maybe Text          -- Direct API key (from env, runtime)
    , pcVertexConfig :: Maybe VertexConfig  -- Only for Vertex AI
    }
    deriving (Eq, Show)

-- | Full gateway configuration
data Config = Config
    { cfgPort :: Int
    , cfgHost :: Text
    , cfgVenice :: ProviderConfig
    , cfgVertex :: ProviderConfig
    , cfgBaseten :: ProviderConfig
    , cfgOpenRouter :: ProviderConfig
    , cfgLogLevel :: Text             -- "debug" | "info" | "warn" | "error"
    , cfgRequestTimeout :: Int        -- Seconds
    , cfgMaxRetries :: Int
    }
    deriving (Eq, Show)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // defaults
-- ════════════════════════════════════════════════════════════════════════════

-- | Default configuration with standard provider URLs
defaultConfig :: Config
defaultConfig = Config
    { cfgPort = 8080
    , cfgHost = "0.0.0.0"
    , cfgVenice = ProviderConfig
        { pcEnabled = True
        , pcBaseUrl = "https://api.venice.ai/api/v1"
        , pcApiKeyPath = Nothing
        , pcApiKey = Nothing
        , pcVertexConfig = Nothing
        }
    , cfgVertex = ProviderConfig
        { pcEnabled = True
        , pcBaseUrl = ""  -- Constructed from project/location
        , pcApiKeyPath = Nothing
        , pcApiKey = Nothing
        , pcVertexConfig = Just VertexConfig
            { vcProjectId = ""
            , vcLocation = "us-central1"
            , vcServiceAccountKeyPath = Nothing
            }
        }
    , cfgBaseten = ProviderConfig
        { pcEnabled = True
        , pcBaseUrl = "https://inference.baseten.co/v1"
        , pcApiKeyPath = Nothing
        , pcApiKey = Nothing
        , pcVertexConfig = Nothing
        }
    , cfgOpenRouter = ProviderConfig
        { pcEnabled = True
        , pcBaseUrl = "https://openrouter.ai/api/v1"
        , pcApiKeyPath = Nothing
        , pcApiKey = Nothing
        , pcVertexConfig = Nothing
        }
    , cfgLogLevel = "info"
    , cfgRequestTimeout = 120
    , cfgMaxRetries = 3
    }


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // loading
-- ════════════════════════════════════════════════════════════════════════════

-- | Read API key from file, stripping whitespace
-- Uses IOException (not SomeException) for precise error handling
readApiKey :: FilePath -> IO (Maybe Text)
readApiKey path = do
    result <- try @IOException $ TIO.readFile path
    pure $ case result of
        Left _ -> Nothing
        Right content -> Just $ T.strip content

-- | Load API key from path or environment variable
loadApiKey :: Maybe FilePath -> Maybe Text -> Text -> IO (Maybe Text)
loadApiKey mPath mDirect envVar = do
    -- Priority: direct > file > env
    case mDirect of
        Just key -> pure $ Just key
        Nothing -> case mPath of
            Just path -> do
                keyFromFile <- readApiKey path
                case keyFromFile of
                    Just k -> pure $ Just k
                    Nothing -> fmap T.pack <$> lookupEnv (T.unpack envVar)
            Nothing -> fmap T.pack <$> lookupEnv (T.unpack envVar)

-- | Load configuration from environment variables
--
-- Environment variables:
--   STRAYLIGHT_PORT           - Server port (default: 8080)
--   STRAYLIGHT_HOST           - Server host (default: 0.0.0.0)
--   STRAYLIGHT_LOG_LEVEL      - Log level (default: info)
--
--   VENICE_API_KEY            - Venice AI API key
--   VENICE_API_KEY_FILE       - Path to Venice API key file
--
--   GOOGLE_CLOUD_PROJECT      - GCP project ID for Vertex AI
--   VERTEX_LOCATION           - Vertex AI location (default: us-central1)
--   GOOGLE_APPLICATION_CREDENTIALS - Path to service account key
--
--   BASETEN_API_KEY           - Baseten API key
--   BASETEN_API_KEY_FILE      - Path to Baseten API key file
--
--   OPENROUTER_API_KEY        - OpenRouter API key
--   OPENROUTER_API_KEY_FILE   - Path to OpenRouter API key file
loadConfigFromEnv :: IO Config
loadConfigFromEnv = do
    -- Server settings (use readMaybe, never partial read)
    port <- fromMaybe 8080 . (>>= readMaybe) <$> lookupEnv "STRAYLIGHT_PORT"
    host <- maybe "0.0.0.0" T.pack <$> lookupEnv "STRAYLIGHT_HOST"
    logLevel <- maybe "info" T.pack <$> lookupEnv "STRAYLIGHT_LOG_LEVEL"

    -- Venice
    veniceKeyFile <- lookupEnv "VENICE_API_KEY_FILE"
    veniceKey <- loadApiKey veniceKeyFile Nothing "VENICE_API_KEY"

    -- Vertex (uses ADC or service account)
    gcpProject <- maybe "" T.pack <$> lookupEnv "GOOGLE_CLOUD_PROJECT"
    vertexLocation <- maybe "us-central1" T.pack <$> lookupEnv "VERTEX_LOCATION"
    gcpCredentials <- lookupEnv "GOOGLE_APPLICATION_CREDENTIALS"

    -- Baseten
    basetenKeyFile <- lookupEnv "BASETEN_API_KEY_FILE"
    basetenKey <- loadApiKey basetenKeyFile Nothing "BASETEN_API_KEY"

    -- OpenRouter
    openrouterKeyFile <- lookupEnv "OPENROUTER_API_KEY_FILE"
    openrouterKey <- loadApiKey openrouterKeyFile Nothing "OPENROUTER_API_KEY"

    let vertexBaseUrl = if T.null gcpProject
            then ""
            else "https://" <> vertexLocation <> "-aiplatform.googleapis.com/v1/projects/"
                 <> gcpProject <> "/locations/" <> vertexLocation <> "/endpoints/openapi"

    pure Config
        { cfgPort = port
        , cfgHost = host
        , cfgVenice = ProviderConfig
            { pcEnabled = veniceKey /= Nothing
            , pcBaseUrl = "https://api.venice.ai/api/v1"
            , pcApiKeyPath = veniceKeyFile
            , pcApiKey = veniceKey
            , pcVertexConfig = Nothing
            }
        , cfgVertex = ProviderConfig
            { pcEnabled = not (T.null gcpProject)
            , pcBaseUrl = vertexBaseUrl
            , pcApiKeyPath = Nothing
            , pcApiKey = Nothing  -- Uses OAuth, not API key
            , pcVertexConfig = Just VertexConfig
                { vcProjectId = gcpProject
                , vcLocation = vertexLocation
                , vcServiceAccountKeyPath = gcpCredentials
                }
            }
        , cfgBaseten = ProviderConfig
            { pcEnabled = basetenKey /= Nothing
            , pcBaseUrl = "https://inference.baseten.co/v1"
            , pcApiKeyPath = basetenKeyFile
            , pcApiKey = basetenKey
            , pcVertexConfig = Nothing
            }
        , cfgOpenRouter = ProviderConfig
            { pcEnabled = openrouterKey /= Nothing
            , pcBaseUrl = "https://openrouter.ai/api/v1"
            , pcApiKeyPath = openrouterKeyFile
            , pcApiKey = openrouterKey
            , pcVertexConfig = Nothing
            }
        , cfgLogLevel = logLevel
        , cfgRequestTimeout = 120
        , cfgMaxRetries = 3
        }

-- | Load configuration (currently just from env, could add file support)
loadConfig :: IO Config
loadConfig = loadConfigFromEnv
