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
    Config
      ( Config,
        cfgPort,
        cfgHost,
        cfgTriton,
        -- High-throughput providers (no rate limits, MoE optimized)
        cfgTogether,
        cfgSambaNova,
        cfgFireworks,
        cfgNovita,
        cfgDeepInfra,
        cfgModal,
        cfgGroq,
        cfgCerebras,
        -- Standard providers
        cfgVenice,
        cfgVertex,
        cfgBaseten,
        cfgOpenRouter,
        cfgAnthropic,
        cfgLogLevel,
        cfgRequestTimeout,
        cfgMaxRetries,
        cfgAdminApiKey,
        cfgCacheConfig,
        cfgPoolConfig
      ),
    ProviderConfig
      ( ProviderConfig,
        pcEnabled,
        pcBaseUrl,
        pcApiKeyPath,
        pcApiKey,
        pcVertexConfig
      ),
    VertexConfig (VertexConfig, vcProjectId, vcLocation, vcServiceAccountKeyPath),
    ResponseCacheConfig
      ( ResponseCacheConfig,
        rccEnabled,
        rccMaxSize,
        rccTtlSeconds
      ),
    defaultResponseCacheConfig,
    ConnectionPoolConfig
      ( ConnectionPoolConfig,
        cpcConnectionsPerHost,
        cpcIdleConnections,
        cpcIdleTimeoutSeconds
      ),
    defaultConnectionPoolConfig,

    -- * Loading
    loadConfig,
    loadConfigFromEnv,

    -- * Defaults
    defaultConfig,
  )
where

import Control.Exception (IOException, try)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Vertex AI requires OAuth and project configuration
data VertexConfig = VertexConfig
  { vcProjectId :: Text,
    vcLocation :: Text, -- e.g., "us-central1"

    -- | Path to service account JSON key. If Nothing, uses ADC
    -- (Application Default Credentials from gcloud auth)
    vcServiceAccountKeyPath :: Maybe FilePath
  }
  deriving (Eq, Show)

-- | Response cache configuration for semantic deduplication
data ResponseCacheConfig = ResponseCacheConfig
  { -- | Whether response caching is enabled
    rccEnabled :: !Bool,
    -- | Maximum number of cached responses
    rccMaxSize :: !Int,
    -- | TTL for cached responses in seconds
    rccTtlSeconds :: !Int
  }
  deriving (Eq, Show)

-- | Default response cache configuration
defaultResponseCacheConfig :: ResponseCacheConfig
defaultResponseCacheConfig =
  ResponseCacheConfig
    { rccEnabled = True,
      rccMaxSize = 10000,
      rccTtlSeconds = 300 -- 5 minutes
    }

-- | HTTP connection pool configuration
data ConnectionPoolConfig = ConnectionPoolConfig
  { -- | Maximum connections per host (default 100)
    cpcConnectionsPerHost :: !Int,
    -- | Maximum idle connections total (default 200)
    cpcIdleConnections :: !Int,
    -- | Idle connection timeout in seconds (default 60)
    cpcIdleTimeoutSeconds :: !Int
  }
  deriving (Eq, Show)

-- | Default connection pool configuration (optimized for high throughput)
defaultConnectionPoolConfig :: ConnectionPoolConfig
defaultConnectionPoolConfig =
  ConnectionPoolConfig
    { cpcConnectionsPerHost = 100,
      cpcIdleConnections = 200,
      cpcIdleTimeoutSeconds = 60
    }

-- | Configuration for a single provider
data ProviderConfig = ProviderConfig
  { pcEnabled :: Bool,
    pcBaseUrl :: Text,
    pcApiKeyPath :: Maybe FilePath, -- Path to file containing API key
    pcApiKey :: Maybe Text, -- Direct API key (from env, runtime)
    pcVertexConfig :: Maybe VertexConfig -- Only for Vertex AI
  }
  deriving (Eq, Show)

-- | Full gateway configuration
data Config = Config
  { cfgPort :: Int,
    cfgHost :: Text,
    -- Tier 1: Local inference
    cfgTriton :: ProviderConfig, -- Local Triton/TensorRT-LLM (FIRST in chain)
    -- Tier 2: High-throughput providers (no rate limits, MoE optimized)
    cfgTogether :: ProviderConfig, -- Together AI - OpenAI-compatible, fast open models
    cfgSambaNova :: ProviderConfig, -- SambaNova - RDU hardware, massive throughput
    cfgFireworks :: ProviderConfig, -- Fireworks - Optimized inference
    cfgNovita :: ProviderConfig, -- Novita AI - NO rate limits
    cfgDeepInfra :: ProviderConfig, -- DeepInfra - Good open model coverage
    cfgModal :: ProviderConfig, -- Modal - Serverless GPU, burst capacity
    cfgGroq :: ProviderConfig, -- Groq - LPU hardware, insane speed
    cfgCerebras :: ProviderConfig, -- Cerebras - Wafer-scale, enterprise throughput
    -- Tier 3: Standard providers
    cfgVenice :: ProviderConfig,
    cfgVertex :: ProviderConfig,
    cfgBaseten :: ProviderConfig,
    cfgOpenRouter :: ProviderConfig,
    cfgAnthropic :: ProviderConfig, -- Direct Anthropic API (last in chain)
    cfgLogLevel :: Text, -- \"debug\" | \"info\" | \"warn\" | \"error\"
    cfgRequestTimeout :: Int, -- Seconds
    cfgMaxRetries :: Int,
    cfgAdminApiKey :: Maybe Text, -- Admin API key for observability endpoints
    cfgCacheConfig :: ResponseCacheConfig, -- Response cache for semantic deduplication
    cfgPoolConfig :: ConnectionPoolConfig -- HTTP connection pool settings
  }
  deriving (Eq, Show)

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // defaults
-- ════════════════════════════════════════════════════════════════════════════

-- | Default configuration with standard provider URLs
defaultConfig :: Config
defaultConfig =
  Config
    { cfgPort = 8080,
      cfgHost = "0.0.0.0",
      -- Tier 1: Local inference
      cfgTriton =
        ProviderConfig
          { pcEnabled = False, -- Disabled by default (requires local Triton server)
            pcBaseUrl = "http://localhost:9000/v1", -- openai-proxy wrapping Triton
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing, -- Local inference, no auth needed
            pcVertexConfig = Nothing
          },
      -- Tier 2: High-throughput providers (disabled by default, need API keys)
      cfgTogether =
        ProviderConfig
          { pcEnabled = False,
            pcBaseUrl = "https://api.together.xyz/v1",
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig = Nothing
          },
      cfgSambaNova =
        ProviderConfig
          { pcEnabled = False,
            pcBaseUrl = "https://api.sambanova.ai/v1",
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig = Nothing
          },
      cfgFireworks =
        ProviderConfig
          { pcEnabled = False,
            pcBaseUrl = "https://api.fireworks.ai/inference/v1",
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig = Nothing
          },
      cfgNovita =
        ProviderConfig
          { pcEnabled = False,
            pcBaseUrl = "https://api.novita.ai/v3/openai",
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig = Nothing
          },
      cfgDeepInfra =
        ProviderConfig
          { pcEnabled = False,
            pcBaseUrl = "https://api.deepinfra.com/v1/openai",
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig = Nothing
          },
      cfgModal =
        ProviderConfig
          { pcEnabled = False,
            pcBaseUrl = "", -- Modal requires custom endpoint per deployment
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig = Nothing
          },
      cfgGroq =
        ProviderConfig
          { pcEnabled = False,
            pcBaseUrl = "https://api.groq.com/openai/v1",
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig = Nothing
          },
      cfgCerebras =
        ProviderConfig
          { pcEnabled = False,
            pcBaseUrl = "https://api.cerebras.ai/v1",
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig = Nothing
          },
      -- Tier 3: Standard providers
      cfgVenice =
        ProviderConfig
          { pcEnabled = True,
            pcBaseUrl = "https://api.venice.ai/api/v1",
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig = Nothing
          },
      cfgVertex =
        ProviderConfig
          { pcEnabled = True,
            pcBaseUrl = "", -- Constructed from project/location
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig =
              Just
                VertexConfig
                  { vcProjectId = "",
                    vcLocation = "us-central1",
                    vcServiceAccountKeyPath = Nothing
                  }
          },
      cfgBaseten =
        ProviderConfig
          { pcEnabled = True,
            pcBaseUrl = "https://inference.baseten.co/v1",
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig = Nothing
          },
      cfgOpenRouter =
        ProviderConfig
          { pcEnabled = True,
            pcBaseUrl = "https://openrouter.ai/api/v1",
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig = Nothing
          },
      cfgAnthropic =
        ProviderConfig
          { pcEnabled = True,
            pcBaseUrl = "https://api.anthropic.com/v1",
            pcApiKeyPath = Nothing,
            pcApiKey = Nothing,
            pcVertexConfig = Nothing
          },
      cfgLogLevel = "info",
      cfgRequestTimeout = 120,
      cfgMaxRetries = 3,
      cfgAdminApiKey = Nothing, -- Must be set via ADMIN_API_KEY env var
      cfgCacheConfig = defaultResponseCacheConfig,
      cfgPoolConfig = defaultConnectionPoolConfig
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

-- | Parse boolean from environment variable string
-- Accepts: "true", "1", "yes", "on" (case-insensitive)
parseEnabled :: String -> Bool
parseEnabled s = case map toLower s of
  "true" -> True
  "1" -> True
  "yes" -> True
  "on" -> True
  _ -> False
  where
    toLower c
      | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
      | otherwise = c

-- | Load configuration from environment variables
--
-- Environment variables:
--   STRAYLIGHT_PORT           - Server port (default: 8080)
--   STRAYLIGHT_HOST           - Server host (default: 0.0.0.0)
--   STRAYLIGHT_LOG_LEVEL      - Log level (default: info)
--
--   ADMIN_API_KEY             - Admin API key for observability endpoints
--
--   TRITON_URL                - Triton openai-proxy URL (default: http://localhost:9000/v1)
--   TRITON_ENABLED            - Enable local Triton inference (default: false)
--
--   -- High-throughput providers (Tier 2: no rate limits, MoE optimized)
--   TOGETHER_API_KEY          - Together AI API key
--   TOGETHER_API_KEY_FILE     - Path to Together API key file
--
--   SAMBANOVA_API_KEY         - SambaNova API key (RDU hardware, massive throughput)
--   SAMBANOVA_API_KEY_FILE    - Path to SambaNova API key file
--
--   FIREWORKS_API_KEY         - Fireworks AI API key
--   FIREWORKS_API_KEY_FILE    - Path to Fireworks API key file
--
--   NOVITA_API_KEY            - Novita AI API key (NO rate limits!)
--   NOVITA_API_KEY_FILE       - Path to Novita API key file
--
--   DEEPINFRA_API_KEY         - DeepInfra API key
--   DEEPINFRA_API_KEY_FILE    - Path to DeepInfra API key file
--
--   MODAL_TOKEN_ID            - Modal token ID
--   MODAL_TOKEN_SECRET        - Modal token secret
--   MODAL_ENDPOINT            - Modal custom endpoint URL (required)
--   MODAL_API_KEY_FILE        - Path to Modal token ID file
--
--   GROQ_API_KEY              - Groq API key (LPU hardware, insane speed)
--   GROQ_API_KEY_FILE         - Path to Groq API key file
--
--   CEREBRAS_API_KEY          - Cerebras API key (wafer-scale inference)
--   CEREBRAS_API_KEY_FILE     - Path to Cerebras API key file
--
--   -- Standard providers (Tier 3)
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
--
--   ANTHROPIC_API_KEY         - Anthropic API key
--   ANTHROPIC_API_KEY_FILE    - Path to Anthropic API key file
loadConfigFromEnv :: IO Config
loadConfigFromEnv = do
  -- Server settings (use readMaybe, never partial read)
  port <- fromMaybe 8080 . (>>= readMaybe) <$> lookupEnv "STRAYLIGHT_PORT"
  host <- maybe "0.0.0.0" T.pack <$> lookupEnv "STRAYLIGHT_HOST"
  logLevel <- maybe "info" T.pack <$> lookupEnv "STRAYLIGHT_LOG_LEVEL"

  -- Triton (local TensorRT-LLM inference - FIRST in chain when enabled)
  tritonUrl <- maybe "http://localhost:9000/v1" T.pack <$> lookupEnv "TRITON_URL"
  tritonEnabled <- maybe False parseEnabled <$> lookupEnv "TRITON_ENABLED"

  -- Tier 2: High-throughput providers (no rate limits, MoE optimized)
  -- Together AI
  togetherKeyFile <- lookupEnv "TOGETHER_API_KEY_FILE"
  togetherKey <- loadApiKey togetherKeyFile Nothing "TOGETHER_API_KEY"

  -- SambaNova (Chris Ré's RDU hardware)
  sambanovaKeyFile <- lookupEnv "SAMBANOVA_API_KEY_FILE"
  sambanovaKey <- loadApiKey sambanovaKeyFile Nothing "SAMBANOVA_API_KEY"

  -- Fireworks
  fireworksKeyFile <- lookupEnv "FIREWORKS_API_KEY_FILE"
  fireworksKey <- loadApiKey fireworksKeyFile Nothing "FIREWORKS_API_KEY"

  -- Novita AI (NO rate limits)
  novitaKeyFile <- lookupEnv "NOVITA_API_KEY_FILE"
  novitaKey <- loadApiKey novitaKeyFile Nothing "NOVITA_API_KEY"

  -- DeepInfra
  deepinfraKeyFile <- lookupEnv "DEEPINFRA_API_KEY_FILE"
  deepinfraKey <- loadApiKey deepinfraKeyFile Nothing "DEEPINFRA_API_KEY"

  -- Modal (requires custom endpoint URL)
  modalKeyFile <- lookupEnv "MODAL_API_KEY_FILE"
  modalKey <- loadApiKey modalKeyFile Nothing "MODAL_TOKEN_ID"
  _modalSecret <- loadApiKey Nothing Nothing "MODAL_TOKEN_SECRET" -- TODO: use for auth
  modalEndpoint <- maybe "" T.pack <$> lookupEnv "MODAL_ENDPOINT"

  -- Groq (LPU hardware, insane speed)
  groqKeyFile <- lookupEnv "GROQ_API_KEY_FILE"
  groqKey <- loadApiKey groqKeyFile Nothing "GROQ_API_KEY"

  -- Cerebras (wafer-scale inference)
  cerebrasKeyFile <- lookupEnv "CEREBRAS_API_KEY_FILE"
  cerebrasKey <- loadApiKey cerebrasKeyFile Nothing "CEREBRAS_API_KEY"

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

  -- Anthropic (direct API - last in fallback chain)
  anthropicKeyFile <- lookupEnv "ANTHROPIC_API_KEY_FILE"
  anthropicKey <- loadApiKey anthropicKeyFile Nothing "ANTHROPIC_API_KEY"

  -- Admin API key for observability endpoints
  adminApiKey <- fmap T.pack <$> lookupEnv "ADMIN_API_KEY"

  -- Response cache configuration
  cacheEnabled <- maybe True parseEnabled <$> lookupEnv "CACHE_ENABLED"
  cacheMaxSize <- fromMaybe 10000 . (>>= readMaybe) <$> lookupEnv "CACHE_MAX_SIZE"
  cacheTtl <- fromMaybe 300 . (>>= readMaybe) <$> lookupEnv "CACHE_TTL_SECONDS"
  let cacheConfig =
        ResponseCacheConfig
          { rccEnabled = cacheEnabled,
            rccMaxSize = cacheMaxSize,
            rccTtlSeconds = cacheTtl
          }

  -- Connection pool configuration
  poolConnsPerHost <- fromMaybe 100 . (>>= readMaybe) <$> lookupEnv "POOL_CONNECTIONS_PER_HOST"
  poolIdleConns <- fromMaybe 200 . (>>= readMaybe) <$> lookupEnv "POOL_IDLE_CONNECTIONS"
  poolIdleTimeout <- fromMaybe 60 . (>>= readMaybe) <$> lookupEnv "POOL_IDLE_TIMEOUT_SECONDS"
  let poolConfig =
        ConnectionPoolConfig
          { cpcConnectionsPerHost = poolConnsPerHost,
            cpcIdleConnections = poolIdleConns,
            cpcIdleTimeoutSeconds = poolIdleTimeout
          }

  let vertexBaseUrl =
        if T.null gcpProject
          then ""
          else
            "https://"
              <> vertexLocation
              <> "-aiplatform.googleapis.com/v1/projects/"
              <> gcpProject
              <> "/locations/"
              <> vertexLocation
              <> "/endpoints/openapi"

  pure
    Config
      { cfgPort = port,
        cfgHost = host,
        -- Tier 1: Local inference
        cfgTriton =
          ProviderConfig
            { pcEnabled = tritonEnabled,
              pcBaseUrl = tritonUrl,
              pcApiKeyPath = Nothing,
              pcApiKey = Nothing, -- Local inference, no auth
              pcVertexConfig = Nothing
            },
        -- Tier 2: High-throughput providers (no rate limits, MoE optimized)
        cfgTogether =
          ProviderConfig
            { pcEnabled = togetherKey /= Nothing,
              pcBaseUrl = "https://api.together.xyz/v1",
              pcApiKeyPath = togetherKeyFile,
              pcApiKey = togetherKey,
              pcVertexConfig = Nothing
            },
        cfgSambaNova =
          ProviderConfig
            { pcEnabled = sambanovaKey /= Nothing,
              pcBaseUrl = "https://api.sambanova.ai/v1",
              pcApiKeyPath = sambanovaKeyFile,
              pcApiKey = sambanovaKey,
              pcVertexConfig = Nothing
            },
        cfgFireworks =
          ProviderConfig
            { pcEnabled = fireworksKey /= Nothing,
              pcBaseUrl = "https://api.fireworks.ai/inference/v1",
              pcApiKeyPath = fireworksKeyFile,
              pcApiKey = fireworksKey,
              pcVertexConfig = Nothing
            },
        cfgNovita =
          ProviderConfig
            { pcEnabled = novitaKey /= Nothing,
              pcBaseUrl = "https://api.novita.ai/v3/openai",
              pcApiKeyPath = novitaKeyFile,
              pcApiKey = novitaKey,
              pcVertexConfig = Nothing
            },
        cfgDeepInfra =
          ProviderConfig
            { pcEnabled = deepinfraKey /= Nothing,
              pcBaseUrl = "https://api.deepinfra.com/v1/openai",
              pcApiKeyPath = deepinfraKeyFile,
              pcApiKey = deepinfraKey,
              pcVertexConfig = Nothing
            },
        cfgModal =
          ProviderConfig
            { pcEnabled = modalKey /= Nothing && not (T.null modalEndpoint),
              pcBaseUrl = modalEndpoint, -- Modal requires custom endpoint URL
              pcApiKeyPath = modalKeyFile,
              pcApiKey = modalKey, -- TOKEN_ID, TOKEN_SECRET handled by provider
              pcVertexConfig = Nothing
            },
        cfgGroq =
          ProviderConfig
            { pcEnabled = groqKey /= Nothing,
              pcBaseUrl = "https://api.groq.com/openai/v1",
              pcApiKeyPath = groqKeyFile,
              pcApiKey = groqKey,
              pcVertexConfig = Nothing
            },
        cfgCerebras =
          ProviderConfig
            { pcEnabled = cerebrasKey /= Nothing,
              pcBaseUrl = "https://api.cerebras.ai/v1",
              pcApiKeyPath = cerebrasKeyFile,
              pcApiKey = cerebrasKey,
              pcVertexConfig = Nothing
            },
        -- Tier 3: Standard providers
        cfgVenice =
          ProviderConfig
            { pcEnabled = veniceKey /= Nothing,
              pcBaseUrl = "https://api.venice.ai/api/v1",
              pcApiKeyPath = veniceKeyFile,
              pcApiKey = veniceKey,
              pcVertexConfig = Nothing
            },
        cfgVertex =
          ProviderConfig
            { pcEnabled = not (T.null gcpProject),
              pcBaseUrl = vertexBaseUrl,
              pcApiKeyPath = Nothing,
              pcApiKey = Nothing, -- Uses OAuth, not API key
              pcVertexConfig =
                Just
                  VertexConfig
                    { vcProjectId = gcpProject,
                      vcLocation = vertexLocation,
                      vcServiceAccountKeyPath = gcpCredentials
                    }
            },
        cfgBaseten =
          ProviderConfig
            { pcEnabled = basetenKey /= Nothing,
              pcBaseUrl = "https://inference.baseten.co/v1",
              pcApiKeyPath = basetenKeyFile,
              pcApiKey = basetenKey,
              pcVertexConfig = Nothing
            },
        cfgOpenRouter =
          ProviderConfig
            { pcEnabled = openrouterKey /= Nothing,
              pcBaseUrl = "https://openrouter.ai/api/v1",
              pcApiKeyPath = openrouterKeyFile,
              pcApiKey = openrouterKey,
              pcVertexConfig = Nothing
            },
        cfgAnthropic =
          ProviderConfig
            { pcEnabled = anthropicKey /= Nothing,
              pcBaseUrl = "https://api.anthropic.com/v1",
              pcApiKeyPath = anthropicKeyFile,
              pcApiKey = anthropicKey,
              pcVertexConfig = Nothing
            },
        cfgLogLevel = logLevel,
        cfgRequestTimeout = 120,
        cfgMaxRetries = 3,
        cfgAdminApiKey = adminApiKey,
        cfgCacheConfig = cacheConfig,
        cfgPoolConfig = poolConfig
      }

-- | Load configuration (currently just from env, could add file support)
loadConfig :: IO Config
loadConfig = loadConfigFromEnv
