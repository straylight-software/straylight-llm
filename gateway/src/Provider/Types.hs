-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                       // straylight-llm // provider/types
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The sky above the port was the color of television, tuned to a dead
--      channel."
--
--                                                              — Neuromancer
--
-- Provider abstraction for LLM backends. Each provider implements the same
-- interface, enabling transparent fallback routing.
--
-- All provider operations use GatewayM for effect tracking:
--   - HTTP access recorded as co-effects
--   - Auth usage recorded as co-effects
--   - Latency and token usage recorded in grade
--   - Provider/model recorded in provenance
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}

module Provider.Types
  ( -- * Provider Interface
    Provider (Provider, providerName, providerEnabled, providerChat, providerChatStream, providerEmbeddings, providerModels, providerSupportsModel),
    ProviderName (Triton, Venice, Vertex, Baseten, OpenRouter, Anthropic, LambdaLabs, RunPod, VastAI),
    ProviderResult (Success, Failure, Retry),
    ProviderError (AuthError, RateLimitError, QuotaExceededError, ModelNotFoundError, ProviderUnavailable, InvalidRequestError, InternalError, TimeoutError, UnknownError),

    -- * Request Context
    RequestContext (RequestContext, rcManager, rcRequestId, rcClientIp),

    -- * Streaming
    StreamCallback,
  )
where

import Data.Aeson (FromJSON (parseJSON), ToJSON (toJSON), Value (String))
import Data.ByteString (ByteString)
import Data.Text (Text)
import Effects.Graded (GatewayM)
import Network.HTTP.Client (Manager)
import Types (ChatRequest, ChatResponse, EmbeddingRequest, EmbeddingResponse, ModelList)

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Provider names for the fallback chain
-- Priority: Triton (local) -> Venice -> Vertex -> Baseten -> OpenRouter -> Anthropic
-- Triton is first: local TensorRT-LLM inference (~50-200ms latency)
-- Anthropic is last: direct API access, used when explicitly requested
-- GPU Rate providers: LambdaLabs, RunPod, VastAI (for pricing aggregation only)
data ProviderName
  = Triton
  | Venice
  | Vertex
  | Baseten
  | OpenRouter
  | Anthropic
  | -- GPU rate providers (pricing only, no inference)
    LambdaLabs
  | RunPod
  | VastAI
  deriving (Eq, Show, Ord, Enum, Bounded)

instance ToJSON ProviderName where
  toJSON Triton = "triton"
  toJSON Venice = "venice"
  toJSON Vertex = "vertex"
  toJSON Baseten = "baseten"
  toJSON OpenRouter = "openrouter"
  toJSON Anthropic = "anthropic"
  toJSON LambdaLabs = "lambdalabs"
  toJSON RunPod = "runpod"
  toJSON VastAI = "vastai"

instance FromJSON ProviderName where
  parseJSON (String "triton") = pure Triton
  parseJSON (String "venice") = pure Venice
  parseJSON (String "vertex") = pure Vertex
  parseJSON (String "baseten") = pure Baseten
  parseJSON (String "openrouter") = pure OpenRouter
  parseJSON (String "anthropic") = pure Anthropic
  parseJSON (String "lambdalabs") = pure LambdaLabs
  parseJSON (String "runpod") = pure RunPod
  parseJSON (String "vastai") = pure VastAI
  parseJSON _ = fail "Invalid provider name"

-- | Errors that can occur when calling a provider
data ProviderError
  = AuthError Text -- Authentication failed
  | RateLimitError Text -- Rate limited (429)
  | QuotaExceededError Text -- Quota exhausted
  | ModelNotFoundError Text -- Model not available on this provider
  | ProviderUnavailable Text -- Provider is down or unreachable
  | InvalidRequestError Text -- Bad request (4xx)
  | InternalError Text -- Provider internal error (5xx)
  | TimeoutError Text -- Request timed out
  | UnknownError Text -- Catch-all
  deriving (Eq, Show)

-- | Result of a provider call
data ProviderResult a
  = Success a
  | Failure ProviderError
  | Retry ProviderError -- Failure but should retry with next provider
  deriving (Eq, Show)

-- | Context passed to provider for each request
data RequestContext = RequestContext
  { rcManager :: Manager, -- HTTP connection manager
    rcRequestId :: Text, -- Unique request ID for tracing
    rcClientIp :: Maybe Text -- Original client IP
  }

-- | Callback for streaming responses
-- Called with each SSE chunk (raw bytes)
type StreamCallback = ByteString -> IO ()

-- ════════════════════════════════════════════════════════════════════════════
--                                                      // provider interface
-- ════════════════════════════════════════════════════════════════════════════

-- | Provider interface
-- Each backend (Venice, Vertex, Baseten, OpenAI) implements this.
--
-- All operations return GatewayM for effect tracking:
--   - HTTP access, auth usage recorded as co-effects
--   - Latency, token counts recorded in grade
--   - Provider/model recorded in provenance
data Provider = Provider
  { providerName :: ProviderName,
    -- | Check if provider is configured and ready
    providerEnabled :: GatewayM Bool,
    -- | Non-streaming chat completion
    providerChat :: RequestContext -> ChatRequest -> GatewayM (ProviderResult ChatResponse),
    -- | Streaming chat completion (calls callback with SSE chunks)
    providerChatStream :: RequestContext -> ChatRequest -> StreamCallback -> GatewayM (ProviderResult ()),
    -- | Generate embeddings
    providerEmbeddings :: RequestContext -> EmbeddingRequest -> GatewayM (ProviderResult EmbeddingResponse),
    -- | List available models
    providerModels :: RequestContext -> GatewayM (ProviderResult ModelList),
    -- | Check if this provider supports a given model ID (pure, no effects)
    providerSupportsModel :: Text -> Bool
  }
