-- | Server-Sent Events (SSE) streaming module
-- |
-- | Manages real-time connection to the gateway's event stream for
-- | live updates of requests, provider status, and proofs.
module Straylight.Streaming
  ( -- Event types
    GatewayEvent(..)
  , RequestStartedEvent
  , RequestCompletedEvent
  , ProofGeneratedEvent
  , ProviderStatusEvent
  , MetricsUpdateEvent
    -- Connection management
  , ConnectionState(..)
  , StreamConfig
  , defaultStreamConfig
    -- Halogen subscription
  , subscribeToEvents
  , EventEmitter
  , EventSourceHandle
  , createEventEmitter
  , closeEventEmitter
  ) where

import Prelude

import Data.Argonaut (class DecodeJson, decodeJson, JsonDecodeError(..), printJsonDecodeError)
import Data.Argonaut.Decode.Decoders as Decoders
import Data.Argonaut.Core (toObject, Json)
import Data.Argonaut.Parser (jsonParser)
import Data.Array as Array
import Data.Either (Either(..), hush)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Foreign.Object as Object
import Halogen.Subscription as HS
import Straylight.API.Client as Api


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // event types
-- ════════════════════════════════════════════════════════════════════════════

-- | Events emitted by the gateway SSE stream
data GatewayEvent
  = RequestStarted RequestStartedEvent
  | RequestCompleted RequestCompletedEvent
  | ProofGenerated ProofGeneratedEvent
  | ProviderStatusChanged ProviderStatusEvent
  | MetricsUpdated MetricsUpdateEvent
  | ConnectionOpened
  | ConnectionClosed
  | ConnectionError String
  | UnknownEvent String String  -- eventType, data

-- | A new request has started processing
type RequestStartedEvent =
  { requestId :: String
  , timestamp :: String
  , model :: String
  , provider :: String
  }

-- | A request has completed (success or error)
type RequestCompletedEvent =
  { requestId :: String
  , timestamp :: String
  , provider :: String
  , status :: Api.RequestStatus
  , latencyMs :: Int
  , promptTokens :: Int
  , completionTokens :: Int
  , errorMessage :: Maybe String
  }

-- | A discharge proof has been generated
type ProofGeneratedEvent =
  { requestId :: String
  , proofId :: String
  , timestamp :: String
  , isSigned :: Boolean
  }

-- | A provider's status has changed
type ProviderStatusEvent =
  { provider :: String
  , status :: String  -- "healthy" | "degraded" | "down"
  , circuitBreakerState :: Api.CircuitBreakerState
  , timestamp :: String
  }

-- | Periodic metrics update
type MetricsUpdateEvent =
  { requestsLastMinute :: Int
  , errorRate :: Number
  , avgLatencyMs :: Int
  , timestamp :: String
  }


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // connection state
-- ════════════════════════════════════════════════════════════════════════════

-- | Connection state for the SSE stream
data ConnectionState
  = Connecting
  | Connected
  | Reconnecting Int  -- attempt number
  | Disconnected
  | Failed String     -- error message

derive instance eqConnectionState :: Eq ConnectionState

-- | Configuration for the SSE connection
type StreamConfig =
  { baseUrl :: String
  , port :: Int
  , reconnectDelayMs :: Int
  , maxReconnectAttempts :: Int
  }

defaultStreamConfig :: StreamConfig
defaultStreamConfig =
  { baseUrl: "http://localhost"
  , port: 8080
  , reconnectDelayMs: 1000
  , maxReconnectAttempts: 10
  }

streamUrl :: StreamConfig -> String
streamUrl cfg = cfg.baseUrl <> ":" <> show cfg.port <> "/v1/events"


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // event decoding
-- ════════════════════════════════════════════════════════════════════════════

-- | Parse an SSE event from its type and data
parseEvent :: String -> String -> Either String GatewayEvent
parseEvent eventType dataStr = case eventType of
  "request.started" -> do
    json <- jsonParser dataStr
    event <- decodeRequestStarted json
    Right $ RequestStarted event
  
  "request.completed" -> do
    json <- jsonParser dataStr
    event <- decodeRequestCompleted json
    Right $ RequestCompleted event
  
  "proof.generated" -> do
    json <- jsonParser dataStr
    event <- decodeProofGenerated json
    Right $ ProofGenerated event
  
  "provider.status" -> do
    json <- jsonParser dataStr
    event <- decodeProviderStatus json
    Right $ ProviderStatusChanged event
  
  "metrics.update" -> do
    json <- jsonParser dataStr
    event <- decodeMetricsUpdate json
    Right $ MetricsUpdated event
  
  _ -> Right $ UnknownEvent eventType dataStr

decodeRequestStarted :: Json -> Either String RequestStartedEvent
decodeRequestStarted json = case toObject json of
  Nothing -> Left "Expected object for RequestStartedEvent"
  Just obj -> do
    requestId <- getField obj "requestId"
    timestamp <- getField obj "timestamp"
    model <- getField obj "model"
    provider <- getField obj "provider"
    Right { requestId, timestamp, model, provider }

decodeRequestCompleted :: Json -> Either String RequestCompletedEvent
decodeRequestCompleted json = case toObject json of
  Nothing -> Left "Expected object for RequestCompletedEvent"
  Just obj -> do
    requestId <- getField obj "requestId"
    timestamp <- getField obj "timestamp"
    provider <- getField obj "provider"
    status <- getFieldDecode obj "status" decodeJson
    latencyMs <- getField obj "latencyMs"
    promptTokens <- getField obj "promptTokens"
    completionTokens <- getField obj "completionTokens"
    let errorMessage = hush $ getField obj "errorMessage"
    Right { requestId, timestamp, provider, status, latencyMs, promptTokens, completionTokens, errorMessage }

decodeProofGenerated :: Json -> Either String ProofGeneratedEvent
decodeProofGenerated json = case toObject json of
  Nothing -> Left "Expected object for ProofGeneratedEvent"
  Just obj -> do
    requestId <- getField obj "requestId"
    proofId <- getField obj "proofId"
    timestamp <- getField obj "timestamp"
    isSigned <- getField obj "isSigned"
    Right { requestId, proofId, timestamp, isSigned }

decodeProviderStatus :: Json -> Either String ProviderStatusEvent
decodeProviderStatus json = case toObject json of
  Nothing -> Left "Expected object for ProviderStatusEvent"
  Just obj -> do
    provider <- getField obj "provider"
    status <- getField obj "status"
    circuitBreakerState <- getFieldDecode obj "circuitBreakerState" decodeJson
    timestamp <- getField obj "timestamp"
    Right { provider, status, circuitBreakerState, timestamp }

decodeMetricsUpdate :: Json -> Either String MetricsUpdateEvent
decodeMetricsUpdate json = case toObject json of
  Nothing -> Left "Expected object for MetricsUpdateEvent"
  Just obj -> do
    requestsLastMinute <- getField obj "requestsLastMinute"
    errorRate <- getField obj "errorRate"
    avgLatencyMs <- getField obj "avgLatencyMs"
    timestamp <- getField obj "timestamp"
    Right { requestsLastMinute, errorRate, avgLatencyMs, timestamp }

-- | Helper to get a string field
getField :: forall a. DecodeJson a => Object.Object Json -> String -> Either String a
getField obj key = case Object.lookup key obj of
  Nothing -> Left $ "Missing field: " <> key
  Just val -> case decodeJson val of
    Left err -> Left $ printJsonDecodeError err
    Right v -> Right v

-- | Helper to get a field with custom decoder
getFieldDecode :: forall a. Object.Object Json -> String -> (Json -> Either JsonDecodeError a) -> Either String a
getFieldDecode obj key decoder = case Object.lookup key obj of
  Nothing -> Left $ "Missing field: " <> key
  Just val -> case decoder val of
    Left err -> Left $ printJsonDecodeError err
    Right v -> Right v


-- ════════════════════════════════════════════════════════════════════════════
--                                                       // halogen subscription
-- ════════════════════════════════════════════════════════════════════════════

-- | Opaque handle to the event source
type EventEmitter =
  { emitter :: HS.Emitter GatewayEvent
  , subscription :: HS.Subscription
  , eventSourceRef :: Ref (Maybe EventSourceHandle)
  , stateRef :: Ref ConnectionState
  }

-- | Foreign type for the browser EventSource
foreign import data EventSourceHandle :: Type

-- | Create an event emitter that connects to the SSE stream
createEventEmitter :: StreamConfig -> Effect EventEmitter
createEventEmitter config = do
  { emitter, listener } <- HS.create
  eventSourceRef <- Ref.new Nothing
  stateRef <- Ref.new Connecting
  
  -- Start connection
  let 
    onMessage eventType dataStr = do
      case parseEvent eventType dataStr of
        Left _ -> pure unit  -- Silently ignore parse errors
        Right event -> HS.notify listener event
    
    onOpen = do
      Ref.write Connected stateRef
      HS.notify listener ConnectionOpened
    
    onError errMsg = do
      currentState <- Ref.read stateRef
      case currentState of
        Failed _ -> pure unit  -- Already failed
        _ -> do
          Ref.write (Failed errMsg) stateRef
          HS.notify listener $ ConnectionError errMsg
    
    onClose = do
      Ref.write Disconnected stateRef
      HS.notify listener ConnectionClosed
  
  -- Create the EventSource
  es <- createEventSource (streamUrl config) onMessage onOpen onError onClose
  Ref.write (Just es) eventSourceRef
  
  -- Create subscription (will be used to close)
  subscription <- HS.subscribe emitter (\_ -> pure unit)
  
  pure { emitter, subscription, eventSourceRef, stateRef }

-- | Close the event emitter and disconnect from SSE
closeEventEmitter :: EventEmitter -> Effect Unit
closeEventEmitter ee = do
  maybeEs <- Ref.read ee.eventSourceRef
  case maybeEs of
    Nothing -> pure unit
    Just es -> do
      closeEventSource es
      Ref.write Nothing ee.eventSourceRef
      Ref.write Disconnected ee.stateRef

-- | Subscribe to gateway events in a Halogen component
subscribeToEvents :: forall m. MonadEffect m => EventEmitter -> m (HS.Emitter GatewayEvent)
subscribeToEvents ee = pure ee.emitter


-- ════════════════════════════════════════════════════════════════════════════
--                                                                       // ffi
-- ════════════════════════════════════════════════════════════════════════════

-- | Create an EventSource connection
foreign import createEventSource 
  :: String                           -- URL
  -> (String -> String -> Effect Unit) -- onMessage (eventType, data)
  -> Effect Unit                       -- onOpen
  -> (String -> Effect Unit)           -- onError
  -> Effect Unit                       -- onClose
  -> Effect EventSourceHandle

-- | Close an EventSource connection
foreign import closeEventSource :: EventSourceHandle -> Effect Unit
