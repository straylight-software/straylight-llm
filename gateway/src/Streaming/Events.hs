-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                         // straylight-llm // streaming events
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The matrix has its roots in primitive arcade games, in early
--      graphics programs and military experimentation with cranial jacks."
--
--                                                              — Neuromancer
--
-- Server-Sent Events (SSE) broadcaster for real-time updates.
-- Supports multiple concurrent subscribers with broadcast semantics.
--
-- Event Types:
--   - request.started     : New request in progress
--   - request.completed   : Request finished (success/error)
--   - proof.generated     : Discharge proof ready
--   - provider.status     : Circuit breaker state change
--   - metrics.update      : Periodic metrics push (every 10s)
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Streaming.Events
    ( -- * Event Types
      SSEEvent (SSERequestStarted, SSERequestCompleted, SSEProofGenerated, SSEProviderStatus, SSEMetricsUpdate, SSEKeepalive)
    , EventType (RequestStarted, RequestCompleted, ProofGenerated, ProviderStatus, MetricsUpdate, Keepalive)
    , RequestStartedData (RequestStartedData, rsdRequestId, rsdModel, rsdTimestamp)
    , RequestCompletedData (RequestCompletedData, rcdRequestId, rcdModel, rcdProvider, rcdSuccess, rcdLatencyMs, rcdError, rcdTimestamp)
    , ProofGeneratedData (ProofGeneratedData, pgdRequestId, pgdCoeffects, pgdSigned, pgdTimestamp)
    , ProviderStatusData (ProviderStatusData, psdProvider, psdState, psdFailures, psdThreshold, psdLastFailure, psdTimestamp)
    , CircuitState (CircuitClosed, CircuitOpen, CircuitHalfOpen)

      -- * Broadcaster
    , EventBroadcaster
    , newEventBroadcaster
    , subscribe
    , unsubscribe
    , broadcast

      -- * Event Emission Helpers
    , emitRequestStarted
    , emitRequestCompleted
    , emitProofGenerated
    , emitProviderStatus
    , emitMetricsUpdate

      -- * Serialization
    , encodeSSEEvent
    ) where

import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Concurrent.STM
    ( TVar
    , TChan
    , atomically
    , newTVarIO
    , readTVar
    , writeTVar
    , newBroadcastTChanIO
    , dupTChan
    , writeTChan
    )
import Control.Monad (forever)
import Data.Aeson (ToJSON (toJSON), object, (.=), encode)
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import Numeric (showHex)
import System.Random (randomIO)


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // event types
-- ════════════════════════════════════════════════════════════════════════════

-- | Event type discriminator
data EventType
    = RequestStarted
    | RequestCompleted
    | ProofGenerated
    | ProviderStatus
    | MetricsUpdate
    | Keepalive
    deriving (Eq, Show)

instance ToJSON EventType where
    toJSON RequestStarted = "request.started"
    toJSON RequestCompleted = "request.completed"
    toJSON ProofGenerated = "proof.generated"
    toJSON ProviderStatus = "provider.status"
    toJSON MetricsUpdate = "metrics.update"
    toJSON Keepalive = "keepalive"

-- | Circuit breaker state
data CircuitState
    = CircuitClosed
    | CircuitOpen
    | CircuitHalfOpen
    deriving (Eq, Show)

instance ToJSON CircuitState where
    toJSON CircuitClosed = "closed"
    toJSON CircuitOpen = "open"
    toJSON CircuitHalfOpen = "half-open"

-- | Data for request.started event
data RequestStartedData = RequestStartedData
    { rsdRequestId :: !Text
    , rsdModel :: !Text
    , rsdTimestamp :: !Text  -- ISO 8601
    }
    deriving (Eq, Show)

instance ToJSON RequestStartedData where
    toJSON RequestStartedData{..} = object
        [ "request_id" .= rsdRequestId
        , "model" .= rsdModel
        , "timestamp" .= rsdTimestamp
        ]

-- | Data for request.completed event
data RequestCompletedData = RequestCompletedData
    { rcdRequestId :: !Text
    , rcdModel :: !Text
    , rcdProvider :: !(Maybe Text)
    , rcdSuccess :: !Bool
    , rcdLatencyMs :: !Double
    , rcdError :: !(Maybe Text)
    , rcdTimestamp :: !Text
    }
    deriving (Eq, Show)

instance ToJSON RequestCompletedData where
    toJSON RequestCompletedData{..} = object
        [ "request_id" .= rcdRequestId
        , "model" .= rcdModel
        , "provider" .= rcdProvider
        , "success" .= rcdSuccess
        , "latency_ms" .= rcdLatencyMs
        , "error" .= rcdError
        , "timestamp" .= rcdTimestamp
        ]

-- | Data for proof.generated event
data ProofGeneratedData = ProofGeneratedData
    { pgdRequestId :: !Text
    , pgdCoeffects :: ![Text]  -- Coeffect type names
    , pgdSigned :: !Bool
    , pgdTimestamp :: !Text
    }
    deriving (Eq, Show)

instance ToJSON ProofGeneratedData where
    toJSON ProofGeneratedData{..} = object
        [ "request_id" .= pgdRequestId
        , "coeffects" .= pgdCoeffects
        , "signed" .= pgdSigned
        , "timestamp" .= pgdTimestamp
        ]

-- | Data for provider.status event
data ProviderStatusData = ProviderStatusData
    { psdProvider :: !Text
    , psdState :: !CircuitState
    , psdFailures :: !Int
    , psdThreshold :: !Int
    , psdLastFailure :: !(Maybe Text)  -- ISO 8601
    , psdTimestamp :: !Text
    }
    deriving (Eq, Show)

instance ToJSON ProviderStatusData where
    toJSON ProviderStatusData{..} = object
        [ "provider" .= psdProvider
        , "state" .= psdState
        , "failures" .= psdFailures
        , "threshold" .= psdThreshold
        , "last_failure" .= psdLastFailure
        , "timestamp" .= psdTimestamp
        ]

-- | SSE event with type and data
data SSEEvent
    = SSERequestStarted RequestStartedData
    | SSERequestCompleted RequestCompletedData
    | SSEProofGenerated ProofGeneratedData
    | SSEProviderStatus ProviderStatusData
    | SSEMetricsUpdate LBS.ByteString  -- Pre-encoded metrics JSON
    | SSEKeepalive
    deriving (Eq, Show)

instance ToJSON SSEEvent where
    toJSON (SSERequestStarted d) = object
        [ "type" .= RequestStarted
        , "data" .= d
        ]
    toJSON (SSERequestCompleted d) = object
        [ "type" .= RequestCompleted
        , "data" .= d
        ]
    toJSON (SSEProofGenerated d) = object
        [ "type" .= ProofGenerated
        , "data" .= d
        ]
    toJSON (SSEProviderStatus d) = object
        [ "type" .= ProviderStatus
        , "data" .= d
        ]
    toJSON (SSEMetricsUpdate _) = object
        [ "type" .= MetricsUpdate
        -- data is pre-encoded, handled specially in encodeSSEEvent
        ]
    toJSON SSEKeepalive = object
        [ "type" .= Keepalive
        ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // broadcaster
-- ════════════════════════════════════════════════════════════════════════════

-- | Unique subscriber ID
newtype SubscriberId = SubscriberId Text
    deriving (Eq, Ord, Show)

-- | Event broadcaster using STM broadcast channel
-- Uses a broadcast pattern: one channel, multiple listeners
data EventBroadcaster = EventBroadcaster
    { ebChannel :: TChan SSEEvent        -- Main broadcast channel
    , ebSubscribers :: TVar (Map SubscriberId (TChan SSEEvent))
    , ebKeepaliveThread :: TVar (Maybe ThreadId)
    }

-- | Create a new event broadcaster
-- Starts a background keepalive thread that broadcasts every 30 seconds
newEventBroadcaster :: IO EventBroadcaster
newEventBroadcaster = do
    chan <- newBroadcastTChanIO
    subs <- newTVarIO Map.empty
    keepaliveRef <- newTVarIO Nothing
    
    let broadcaster = EventBroadcaster
            { ebChannel = chan
            , ebSubscribers = subs
            , ebKeepaliveThread = keepaliveRef
            }
    
    -- Start keepalive thread
    tid <- forkIO $ keepaliveLoop broadcaster
    atomically $ writeTVar keepaliveRef (Just tid)
    
    pure broadcaster
  where
    keepaliveLoop :: EventBroadcaster -> IO ()
    keepaliveLoop bc = forever $ do
        threadDelay (30 * 1000000)  -- 30 seconds
        broadcast bc SSEKeepalive

-- | Subscribe to events, returns a channel to read from and cleanup action
subscribe :: EventBroadcaster -> IO (SubscriberId, TChan SSEEvent, IO ())
subscribe bc = do
    -- Generate unique subscriber ID
    n <- randomIO :: IO Word64
    let subId = SubscriberId $ "sub_" <> T.pack (showHex n "")
    
    -- Duplicate the broadcast channel for this subscriber
    subChan <- atomically $ dupTChan (ebChannel bc)
    
    -- Register subscriber
    atomically $ do
        subs <- readTVar (ebSubscribers bc)
        writeTVar (ebSubscribers bc) (Map.insert subId subChan subs)
    
    -- Return cleanup action
    let cleanup = unsubscribe bc subId
    
    pure (subId, subChan, cleanup)

-- | Unsubscribe from events
unsubscribe :: EventBroadcaster -> SubscriberId -> IO ()
unsubscribe bc subId = atomically $ do
    subs <- readTVar (ebSubscribers bc)
    writeTVar (ebSubscribers bc) (Map.delete subId subs)

-- | Broadcast an event to all subscribers
broadcast :: EventBroadcaster -> SSEEvent -> IO ()
broadcast bc event = atomically $
    writeTChan (ebChannel bc) event


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // emission helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Emit request started event
emitRequestStarted :: EventBroadcaster -> Text -> Text -> Text -> IO ()
emitRequestStarted bc requestId model timestamp =
    broadcast bc $ SSERequestStarted RequestStartedData
        { rsdRequestId = requestId
        , rsdModel = model
        , rsdTimestamp = timestamp
        }

-- | Emit request completed event
emitRequestCompleted :: EventBroadcaster -> Text -> Text -> Maybe Text -> Bool -> Double -> Maybe Text -> Text -> IO ()
emitRequestCompleted bc requestId model provider success latencyMs errMsg timestamp =
    broadcast bc $ SSERequestCompleted RequestCompletedData
        { rcdRequestId = requestId
        , rcdModel = model
        , rcdProvider = provider
        , rcdSuccess = success
        , rcdLatencyMs = latencyMs
        , rcdError = errMsg
        , rcdTimestamp = timestamp
        }

-- | Emit proof generated event
emitProofGenerated :: EventBroadcaster -> Text -> [Text] -> Bool -> Text -> IO ()
emitProofGenerated bc requestId coeffects signed timestamp =
    broadcast bc $ SSEProofGenerated ProofGeneratedData
        { pgdRequestId = requestId
        , pgdCoeffects = coeffects
        , pgdSigned = signed
        , pgdTimestamp = timestamp
        }

-- | Emit provider status change event
emitProviderStatus :: EventBroadcaster -> Text -> CircuitState -> Int -> Int -> Maybe Text -> Text -> IO ()
emitProviderStatus bc provider state failures threshold lastFailure timestamp =
    broadcast bc $ SSEProviderStatus ProviderStatusData
        { psdProvider = provider
        , psdState = state
        , psdFailures = failures
        , psdThreshold = threshold
        , psdLastFailure = lastFailure
        , psdTimestamp = timestamp
        }

-- | Emit metrics update event with pre-encoded JSON
emitMetricsUpdate :: EventBroadcaster -> LBS.ByteString -> IO ()
emitMetricsUpdate bc metricsJson =
    broadcast bc $ SSEMetricsUpdate metricsJson


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // serialization
-- ════════════════════════════════════════════════════════════════════════════

-- | Encode SSE event to wire format (event: ...\ndata: ...\n\n)
encodeSSEEvent :: SSEEvent -> LBS.ByteString
encodeSSEEvent event = case event of
    SSEKeepalive ->
        -- Keepalive is just a comment (starts with :)
        ": keepalive\n\n"
    
    SSEMetricsUpdate metricsJson ->
        -- Metrics have pre-encoded data
        "event: metrics.update\ndata: " <> metricsJson <> "\n\n"
    
    SSERequestStarted d ->
        "event: request.started\ndata: " <> encode d <> "\n\n"
    
    SSERequestCompleted d ->
        "event: request.completed\ndata: " <> encode d <> "\n\n"
    
    SSEProofGenerated d ->
        "event: proof.generated\ndata: " <> encode d <> "\n\n"
    
    SSEProviderStatus d ->
        "event: provider.status\ndata: " <> encode d <> "\n\n"
