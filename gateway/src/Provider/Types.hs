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
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Provider.Types
    ( -- * Provider Interface
      Provider (..)
    , ProviderName (..)
    , ProviderResult (..)
    , ProviderError (..)

      -- * Request Context
    , RequestContext (..)

      -- * Streaming
    , StreamCallback
    ) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Network.HTTP.Client (Manager)

import Types (ChatRequest, ChatResponse, EmbeddingRequest, EmbeddingResponse, ModelList)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Provider names for the fallback chain
-- Priority: Venice -> Vertex -> Baseten -> OpenRouter
data ProviderName = Venice | Vertex | Baseten | OpenRouter
    deriving (Eq, Show, Ord, Enum, Bounded)

-- | Errors that can occur when calling a provider
data ProviderError
    = AuthError Text              -- Authentication failed
    | RateLimitError Text         -- Rate limited (429)
    | QuotaExceededError Text     -- Quota exhausted
    | ModelNotFoundError Text     -- Model not available on this provider
    | ProviderUnavailable Text    -- Provider is down or unreachable
    | InvalidRequestError Text    -- Bad request (4xx)
    | InternalError Text          -- Provider internal error (5xx)
    | TimeoutError Text           -- Request timed out
    | UnknownError Text           -- Catch-all
    deriving (Eq, Show)

-- | Result of a provider call
data ProviderResult a
    = Success a
    | Failure ProviderError
    | Retry ProviderError         -- Failure but should retry with next provider
    deriving (Eq, Show)

-- | Context passed to provider for each request
data RequestContext = RequestContext
    { rcManager :: Manager        -- HTTP connection manager
    , rcRequestId :: Text         -- Unique request ID for tracing
    , rcClientIp :: Maybe Text    -- Original client IP
    }

-- | Callback for streaming responses
-- Called with each SSE chunk (raw bytes)
type StreamCallback = ByteString -> IO ()


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // provider interface
-- ════════════════════════════════════════════════════════════════════════════

-- | Provider interface
-- Each backend (Venice, Vertex, Baseten, OpenAI) implements this
data Provider = Provider
    { providerName :: ProviderName

    , providerEnabled :: IO Bool
    -- ^ Check if provider is configured and ready

    , providerChat :: RequestContext -> ChatRequest -> IO (ProviderResult ChatResponse)
    -- ^ Non-streaming chat completion

    , providerChatStream :: RequestContext -> ChatRequest -> StreamCallback -> IO (ProviderResult ())
    -- ^ Streaming chat completion (calls callback with SSE chunks)

    , providerEmbeddings :: RequestContext -> EmbeddingRequest -> IO (ProviderResult EmbeddingResponse)
    -- ^ Generate embeddings

    , providerModels :: RequestContext -> IO (ProviderResult ModelList)
    -- ^ List available models

    , providerSupportsModel :: Text -> Bool
    -- ^ Check if this provider supports a given model ID
    }
