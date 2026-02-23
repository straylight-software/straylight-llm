-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                 // straylight-llm // api
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The matrix has its roots in primitive arcade games."
--
--                                                              — Neuromancer
--
-- Servant API definition for OpenAI-compatible LLM gateway.
-- Implements the core OpenAI API endpoints:
--   - POST /v1/chat/completions
--   - POST /v1/completions
--   - POST /v1/embeddings
--   - GET  /v1/models
--   - GET  /health
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api
    ( -- * API Type
      GatewayAPI
    , api

      -- * Sub-APIs
    , ChatAPI
    , ChatStreamAPI
    , CompletionsAPI
    , EmbeddingsAPI
    , ModelsAPI
    , HealthAPI
    , ProofAPI
    , ProofVerifyAPI
    , ProvidersStatusAPI
    , MetricsAPI
    , RequestsAPI
    , RequestDetailAPI
    , EventsAPI
    , ConfigGetAPI
    , ConfigPutAPI

      -- * Types
    , HealthResponse (HealthResponse, hrStatus, hrVersion)
    , ProvidersStatusResponse (ProvidersStatusResponse, psrProviders)
    , ProviderStatus (ProviderStatus, psName, psCircuitState, psStats)
    , MetricsResponse (MetricsResponse, mrMetrics)
    , RequestsResponse (RequestsResponse, rrRequests, rrTotal)
    , RequestDetailResponse (..)
    , ConfigResponse (..)
    , ConfigUpdateRequest (..)
    , ProofVerifyResponse (..)
    ) where

import Data.Aeson (ToJSON (toJSON), FromJSON (parseJSON), Value, object, (.=), (.:), (.:?), withObject)
import Data.Text (Text)
import Servant

import Coeffect.Types (DischargeProof)
import Provider.Types (ProviderName)
import Resilience.CircuitBreaker (CircuitState, CircuitStats)
import Resilience.Metrics (Metrics)
import Types


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // endpoints
-- ════════════════════════════════════════════════════════════════════════════

-- | Health check endpoint
type HealthAPI = "health" :> Get '[JSON] HealthResponse

-- | Health response
data HealthResponse = HealthResponse
    { hrStatus :: String
    , hrVersion :: String
    }

instance ToJSON HealthResponse where
    toJSON hr = object
        [ "status" .= hrStatus hr
        , "version" .= hrVersion hr
        ]

instance FromJSON HealthResponse where
    parseJSON = withObject "HealthResponse" $ \v -> HealthResponse
        <$> v .: "status"
        <*> v .: "version"

-- | Provider status response
data ProviderStatus = ProviderStatus
    { psName :: ProviderName
    , psCircuitState :: CircuitState
    , psStats :: CircuitStats
    }

instance ToJSON ProviderStatus where
    toJSON ps = object
        [ "name" .= psName ps
        , "circuit_state" .= psCircuitState ps
        , "stats" .= psStats ps
        ]

instance FromJSON ProviderStatus where
    parseJSON = withObject "ProviderStatus" $ \v -> ProviderStatus
        <$> v .: "name"
        <*> v .: "circuit_state"
        <*> v .: "stats"

-- | Providers status response
data ProvidersStatusResponse = ProvidersStatusResponse
    { psrProviders :: [ProviderStatus]
    }

instance ToJSON ProvidersStatusResponse where
    toJSON psr = object
        [ "providers" .= psrProviders psr
        ]

instance FromJSON ProvidersStatusResponse where
    parseJSON = withObject "ProvidersStatusResponse" $ \v -> ProvidersStatusResponse
        <$> v .: "providers"

-- | Metrics response
data MetricsResponse = MetricsResponse
    { mrMetrics :: Metrics
    }

instance ToJSON MetricsResponse where
    toJSON mr = object
        [ "metrics" .= mrMetrics mr
        ]

instance FromJSON MetricsResponse where
    parseJSON = withObject "MetricsResponse" $ \v -> MetricsResponse
        <$> v .: "metrics"

-- | Requests response
data RequestsResponse = RequestsResponse
    { rrRequests :: [Value]  -- RequestHistory JSON values
    , rrTotal :: Int
    }

instance ToJSON RequestsResponse where
    toJSON rr = object
        [ "requests" .= rrRequests rr
        , "total" .= rrTotal rr
        ]

instance FromJSON RequestsResponse where
    parseJSON = withObject "RequestsResponse" $ \v -> RequestsResponse
        <$> v .: "requests"
        <*> v .: "total"

-- | Single request detail response
data RequestDetailResponse = RequestDetailResponse
    { rdrRequestId :: Text
    , rdrModel :: Text
    , rdrProvider :: Maybe Text
    , rdrSuccess :: Bool
    , rdrLatencyMs :: Double
    , rdrTimestamp :: Text
    , rdrProof :: Maybe Value  -- Discharge proof if available
    }

instance ToJSON RequestDetailResponse where
    toJSON rdr = object
        [ "request_id" .= rdrRequestId rdr
        , "model" .= rdrModel rdr
        , "provider" .= rdrProvider rdr
        , "success" .= rdrSuccess rdr
        , "latency_ms" .= rdrLatencyMs rdr
        , "timestamp" .= rdrTimestamp rdr
        , "proof" .= rdrProof rdr
        ]

instance FromJSON RequestDetailResponse where
    parseJSON = withObject "RequestDetailResponse" $ \v -> RequestDetailResponse
        <$> v .: "request_id"
        <*> v .: "model"
        <*> v .:? "provider"
        <*> v .: "success"
        <*> v .: "latency_ms"
        <*> v .: "timestamp"
        <*> v .:? "proof"

-- | Config response
data ConfigResponse = ConfigResponse
    { crPort :: Int
    , crHost :: Text
    , crLogLevel :: Text
    , crProviders :: [Value]  -- Provider configs
    }

instance ToJSON ConfigResponse where
    toJSON cr = object
        [ "port" .= crPort cr
        , "host" .= crHost cr
        , "log_level" .= crLogLevel cr
        , "providers" .= crProviders cr
        ]

instance FromJSON ConfigResponse where
    parseJSON = withObject "ConfigResponse" $ \v -> ConfigResponse
        <$> v .: "port"
        <*> v .: "host"
        <*> v .: "log_level"
        <*> v .: "providers"

-- | Config update request
data ConfigUpdateRequest = ConfigUpdateRequest
    { curLogLevel :: Maybe Text
    , curProviderUpdates :: Maybe [Value]  -- Provider config updates
    }

instance ToJSON ConfigUpdateRequest where
    toJSON cur = object
        [ "log_level" .= curLogLevel cur
        , "provider_updates" .= curProviderUpdates cur
        ]

instance FromJSON ConfigUpdateRequest where
    parseJSON = withObject "ConfigUpdateRequest" $ \v -> ConfigUpdateRequest
        <$> v .:? "log_level"
        <*> v .:? "provider_updates"

-- | Proof verification response
data ProofVerifyResponse = ProofVerifyResponse
    { pvrValid :: Bool
    , pvrMessage :: Text
    , pvrDetails :: Maybe Value  -- Verification details
    }

instance ToJSON ProofVerifyResponse where
    toJSON pvr = object
        [ "valid" .= pvrValid pvr
        , "message" .= pvrMessage pvr
        , "details" .= pvrDetails pvr
        ]

instance FromJSON ProofVerifyResponse where
    parseJSON = withObject "ProofVerifyResponse" $ \v -> ProofVerifyResponse
        <$> v .: "valid"
        <*> v .: "message"
        <*> v .:? "details"

-- | Chat completions endpoint (non-streaming)
-- POST /v1/chat/completions
-- Returns X-Request-Id header for proof retrieval
type ChatAPI =
    "v1" :> "chat" :> "completions"
        :> Header "Authorization" Text
        :> ReqBody '[JSON] ChatRequest
        :> Post '[JSON] (Headers '[Header "X-Request-Id" Text] ChatResponse)

-- | Chat completions endpoint (streaming SSE)
-- POST /v1/chat/completions/stream
-- Uses Raw to allow SSE streaming via WAI responseStream
-- Returns text/event-stream with OpenAI-compatible SSE chunks
type ChatStreamAPI =
    "v1" :> "chat" :> "completions" :> "stream" :> Raw

-- | Legacy completions endpoint
-- POST /v1/completions
type CompletionsAPI =
    "v1" :> "completions"
        :> Header "Authorization" Text
        :> ReqBody '[JSON] CompletionRequest
        :> Post '[JSON] CompletionResponse

-- | Embeddings endpoint
-- POST /v1/embeddings
type EmbeddingsAPI =
    "v1" :> "embeddings"
        :> Header "Authorization" Text
        :> ReqBody '[JSON] EmbeddingRequest
        :> Post '[JSON] EmbeddingResponse

-- | Models endpoint
-- GET /v1/models
type ModelsAPI =
    "v1" :> "models"
        :> Header "Authorization" Text
        :> Get '[JSON] ModelList

-- | Proof endpoint
-- GET /v1/proof/:requestId — get discharge proof for a request
type ProofAPI =
    "v1" :> "proof"
        :> Capture "requestId" Text
        :> Get '[JSON] DischargeProof

-- | Providers status endpoint (admin only)
-- GET /v1/admin/providers/status — get provider health and circuit breaker states
type ProvidersStatusAPI =
    "v1" :> "admin" :> "providers" :> "status"
        :> Header "Authorization" Text
        :> Get '[JSON] ProvidersStatusResponse

-- | Metrics endpoint (admin only)
-- GET /v1/admin/metrics — get aggregated metrics snapshot
type MetricsAPI =
    "v1" :> "admin" :> "metrics"
        :> Header "Authorization" Text
        :> Get '[JSON] MetricsResponse

-- | Requests endpoint (admin only)
-- GET /v1/admin/requests?limit=N — get request history with pagination
type RequestsAPI =
    "v1" :> "admin" :> "requests"
        :> Header "Authorization" Text
        :> QueryParam "limit" Int
        :> Get '[JSON] RequestsResponse

-- | Single request detail endpoint (admin only)
-- GET /v1/admin/requests/:requestId — get single request with full context
type RequestDetailAPI =
    "v1" :> "admin" :> "requests"
        :> Capture "requestId" Text
        :> Header "Authorization" Text
        :> Get '[JSON] RequestDetailResponse

-- | Real-time events endpoint (SSE stream)
-- GET /v1/events — server-sent events for real-time updates
type EventsAPI =
    "v1" :> "events" :> Raw

-- | Config endpoint (admin only)
-- GET/PUT /v1/admin/config — read/write gateway configuration
type ConfigGetAPI =
    "v1" :> "admin" :> "config"
        :> Header "Authorization" Text
        :> Get '[JSON] ConfigResponse

type ConfigPutAPI =
    "v1" :> "admin" :> "config"
        :> Header "Authorization" Text
        :> ReqBody '[JSON] ConfigUpdateRequest
        :> Put '[JSON] ConfigResponse

-- | Proof verification endpoint
-- POST /v1/proof/:requestId/verify — verify discharge proof signature
type ProofVerifyAPI =
    "v1" :> "proof"
        :> Capture "requestId" Text
        :> "verify"
        :> Post '[JSON] ProofVerifyResponse


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // combined api
-- ════════════════════════════════════════════════════════════════════════════

-- | Combined gateway API
type GatewayAPI =
         HealthAPI
    :<|> ChatAPI
    :<|> ChatStreamAPI
    :<|> CompletionsAPI
    :<|> EmbeddingsAPI
    :<|> ModelsAPI
    :<|> ProofAPI
    :<|> ProofVerifyAPI
    :<|> ProvidersStatusAPI
    :<|> MetricsAPI
    :<|> RequestsAPI
    :<|> RequestDetailAPI
    :<|> EventsAPI
    :<|> ConfigGetAPI
    :<|> ConfigPutAPI

-- | API proxy
api :: Proxy GatewayAPI
api = Proxy
