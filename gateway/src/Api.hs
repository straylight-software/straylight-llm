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
    , CompletionsAPI
    , EmbeddingsAPI
    , ModelsAPI
    , HealthAPI

      -- * Types
    , HealthResponse (..)
    ) where

import Data.Aeson (ToJSON (..), object, (.=))
import Data.Text (Text)
import Servant

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

-- | Chat completions endpoint
-- POST /v1/chat/completions
-- Supports both streaming (SSE) and non-streaming responses
type ChatAPI =
    "v1" :> "chat" :> "completions"
        :> Header "Authorization" Text
        :> ReqBody '[JSON] ChatRequest
        :> Post '[JSON] ChatResponse

-- TODO: Chat completions with streaming (SSE) - not yet implemented
-- type ChatStreamAPI = ...

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


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // combined api
-- ════════════════════════════════════════════════════════════════════════════

-- | Combined gateway API
type GatewayAPI =
         HealthAPI
    :<|> ChatAPI
    :<|> CompletionsAPI
    :<|> EmbeddingsAPI
    :<|> ModelsAPI

-- | API proxy
api :: Proxy GatewayAPI
api = Proxy
