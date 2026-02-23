-- | Server-Sent Events handler for real-time gateway updates
-- | Connects to /v1/events endpoint for live provider status
module Straylight.API.EventStream
  ( EventType(RequestStarted, RequestCompleted, ProofGenerated, ProviderStatus, Keepalive)
  , CircuitState(Closed, Open, HalfOpen)
  , GatewayEvent
  , RequestStartedPayload
  , RequestCompletedPayload
  , ProviderStatusPayload
  , ProofGeneratedPayload
  , parseEventType
  , parseCircuitState
  ) where

import Prelude

import Data.Maybe (Maybe)


-- | Event types emitted by the gateway SSE endpoint
data EventType
  = RequestStarted
  | RequestCompleted
  | ProofGenerated
  | ProviderStatus
  | Keepalive

derive instance eqEventType :: Eq EventType

-- | Parse event type from string
parseEventType :: String -> Maybe EventType
parseEventType = case _ of
  "request.started" -> Just RequestStarted
  "request.completed" -> Just RequestCompleted
  "proof.generated" -> Just ProofGenerated
  "provider.status" -> Just ProviderStatus
  "keepalive" -> Just Keepalive
  _ -> Nothing

-- | Payload for request.started events
type RequestStartedPayload =
  { requestId :: String
  , model :: String
  , provider :: String
  , timestamp :: String
  }

-- | Payload for request.completed events
type RequestCompletedPayload =
  { requestId :: String
  , success :: Boolean
  , latencyMs :: Int
  , tokensUsed :: Maybe Int
  , timestamp :: String
  }

-- | Payload for provider.status events
type ProviderStatusPayload =
  { provider :: String
  , status :: String  -- "healthy" | "degraded" | "open"
  , circuitState :: String
  , failureCount :: Int
  , lastFailure :: Maybe String
  }

-- | Payload for proof.generated events
type ProofGeneratedPayload =
  { requestId :: String
  , coeffectCount :: Int
  , signed :: Boolean
  }

-- | Union type for gateway events
type GatewayEvent =
  { eventType :: String
  , payload :: String  -- JSON string, parsed by consumer
  , timestamp :: String
  }

-- | Circuit breaker states
data CircuitState
  = Closed    -- Healthy, requests flow through
  | Open      -- Tripped, failing fast
  | HalfOpen  -- Testing recovery

derive instance eqCircuitState :: Eq CircuitState

-- | Parse circuit state from string
parseCircuitState :: String -> Maybe CircuitState
parseCircuitState = case _ of
  "closed" -> Just Closed
  "open" -> Just Open
  "half-open" -> Just HalfOpen
  _ -> Nothing

-- | Display circuit state
circuitStateLabel :: CircuitState -> String
circuitStateLabel = case _ of
  Closed -> "Healthy"
  Open -> "Circuit Open"
  HalfOpen -> "Recovering"
