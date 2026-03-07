-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                      // straylight-llm // transport // zmq server
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd operated on an almost permanent adrenaline high, a byproduct of
--      youth and proficiency, jacked into a custom cyberspace deck that
--      projected his disembodied consciousness into the consensual
--      hallucination that was the matrix."
--
--                                                              — Neuromancer
--
-- ZMQ server loop for processing inbound SIGIL requests.
--
-- This module runs a concurrent server that:
--   1. Receives requests from downstream products via ZMQ ROUTER socket
--   2. Routes them through the provider chain (same as HTTP path)
--   3. For non-streaming: sends JSON response back via ROUTER
--   4. For streaming: pipes SSE through SigilBridge → SIGIL frames → ZMQ PUB
--
-- Architecture:
--   ZMQ ROUTER (tcp://*:5556) <- requests from omegacode, strayforge, converge
--   ZMQ PUB (tcp://*:5555) -> streaming SIGIL frames (topic: stream/<request_id>)
--
-- The key insight: streaming requests don't get a response via ROUTER.
-- Instead, the client subscribes to the PUB socket with their request_id
-- as topic prefix, and receives clean SIGIL frames. The ROUTER only sends
-- an ack when the stream completes (or error if it fails).
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module Transport.ZmqServer
  ( -- * Server lifecycle
    runZmqServer,
    ZmqServerConfig (..),
    defaultZmqServerConfig,
  )
where

-- ────────────────────────────────────────────────────────────────────────────
--                                                                 // imports
-- ────────────────────────────────────────────────────────────────────────────

import Control.Concurrent.Async (async)
import Control.Exception (SomeException, catch)
import Control.Monad (forever)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)

import Config (SigilConfig (scBindAddress, scEnabled, scInboundAddress))
import Resilience.Metrics
  ( LatencyBuckets (lbCount, lbLe005, lbLe01, lbLe025, lbLe05, lbLe1, lbLe10, lbLe100s, lbLe25, lbLe25s, lbLe5, lbLe50s),
    MetricsStore,
    getMetrics,
    mLatency,
  )
import Router (Router, routeChat, routeChatStream, routerDefaultModel, routerMetrics, routerSigilPublisher)
import Streaming.SigilBridge
  ( BridgeConfig,
    SigilBridge (SigilBridge, sbState, sbPublisher, sbMetadata),
    defaultBridgeConfig,
    finalizeBridge,
    newBridgeState,
    processSseChunk,
  )
import Transport.Zmq (SigilPublisher, newStreamMetadata)
import Transport.ZmqInbound
  ( InboundConfig (..),
    SigilReceiver,
    SigilRequest (..),
    closeSigilReceiver,
    newSigilReceiver,
    receiveRequest,
    sendError,
    sendResponse,
  )
import Types
  ( ChatRequest (ChatRequest, crStream),
    ChatResponse (ChatResponse, respId, respObject, respCreated, respModel, respChoices, respUsage, respSystemFingerprint),
    Choice (Choice),
    FinishReason (FinishReason),
    Message (Message),
    ModelId (ModelId),
    ResponseId (ResponseId),
    Role (Assistant),
    Timestamp (Timestamp),
    Usage (Usage, usagePromptTokens, usageCompletionTokens, usageTotalTokens),
    crModel,
    unModelId,
  )

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Server configuration
data ZmqServerConfig = ZmqServerConfig
  { zscInboundAddress :: !Text,
    -- ^ ROUTER socket bind address (default: "tcp://*:5556")
    zscEgressAddress :: !Text,
    -- ^ PUB socket bind address (default: "tcp://*:5555")
    zscWorkerCount :: !Int
    -- ^ Number of worker threads (default: 4)
  }
  deriving (Show, Eq)

-- | Default server configuration
defaultZmqServerConfig :: ZmqServerConfig
defaultZmqServerConfig =
  ZmqServerConfig
    { zscInboundAddress = "tcp://*:5556",
      zscEgressAddress = "tcp://*:5555",
      zscWorkerCount = 4
    }

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // server lifecycle
-- ════════════════════════════════════════════════════════════════════════════

-- | Run the ZMQ server
--
-- This starts:
--   1. ZMQ ROUTER socket for receiving requests
--   2. Main loop that receives, routes, and responds
--
-- The PUB socket for streaming is managed by the Router (routerSigilPublisher).
runZmqServer :: SigilConfig -> Router -> IO ()
runZmqServer sigilCfg router = do
  if not (scEnabled sigilCfg)
    then TIO.putStrLn "SIGIL transport disabled"
    else do
      TIO.putStrLn $ "Starting SIGIL inbound server on " <> scInboundAddress sigilCfg

      -- Create config from SigilConfig
      let cfg = ZmqServerConfig
            { zscInboundAddress = scInboundAddress sigilCfg,
              zscEgressAddress = scBindAddress sigilCfg,
              zscWorkerCount = 4
            }

      -- Create receiver
      receiver <- newSigilReceiver InboundConfig
        { icBindAddress = zscInboundAddress cfg,
          icReceiveTimeoutMs = -1  -- block forever
        }

      -- Run the main loop with proper cleanup
      runServerLoop receiver router
        `catch` \(e :: SomeException) -> do
          TIO.putStrLn $ "  SIGIL server error: " <> T.pack (show e)
          closeSigilReceiver receiver

-- | Main server loop
runServerLoop :: SigilReceiver -> Router -> IO ()
runServerLoop receiver router = forever $ do
  -- Receive next request (blocks)
  result <- receiveRequest receiver

  case result of
    Left err -> do
      -- Log error but continue (don't crash the server)
      TIO.putStrLn $ "[sigil] receive error: " <> err
    Right req -> do
      -- Handle request in a separate async task
      -- Exceptions in handlers are caught inside handleRequest
      _ <- async $ handleRequest receiver router req
      pure ()

-- ════════════════════════════════════════════════════════════════════════════
--                                                          // request handling
-- ════════════════════════════════════════════════════════════════════════════

-- | Handle a single request
--
-- Wraps all work in exception handler to ensure errors are logged and
-- error responses are sent back to the client via ROUTER.
handleRequest :: SigilReceiver -> Router -> SigilRequest -> IO ()
handleRequest receiver router req@SigilRequest {..} = do
  handleRequestInner receiver router req
    `catch` \(e :: SomeException) -> do
      -- Log the exception and send error response
      TIO.putStrLn $ "  SIGIL exception: " <> reqRequestId <> " " <> T.pack (show e)
      sendError receiver reqIdentity reqRequestId (T.pack (show e))

-- | Inner request handler (may throw exceptions)
--
-- Routes streaming requests through SigilBridge for SSE→SIGIL conversion.
-- Routes non-streaming requests directly and sends JSON response.
handleRequestInner :: SigilReceiver -> Router -> SigilRequest -> IO ()
handleRequestInner receiver router SigilRequest {..} = do
  -- Extract request details
  let chatReq :: ChatRequest
      chatReq = reqChatRequest
      modelId = unModelId (crModel chatReq)
      isStreaming = crStream chatReq == Just True

  TIO.putStrLn $ "  SIGIL request: " <> reqRequestId <> " model=" <> modelId
    <> if isStreaming then " [streaming]" else ""

  if isStreaming
    then handleStreamingRequest receiver router reqIdentity reqRequestId modelId chatReq
    else handleNonStreamingRequest receiver router reqIdentity reqRequestId chatReq

-- | Handle non-streaming request
--
-- Routes through provider chain and sends JSON response back via ROUTER.
handleNonStreamingRequest :: SigilReceiver -> Router -> ByteString -> Text -> ChatRequest -> IO ()
handleNonStreamingRequest receiver router identity requestId chatReq = do
  result <- routeChat router requestId chatReq
  case result of
    Right response -> do
      TIO.putStrLn $ "  SIGIL response: " <> requestId <> " success"
      sendResponse receiver identity requestId response
    Left err -> do
      TIO.putStrLn $ "  SIGIL error: " <> requestId <> " " <> T.pack (show err)
      sendError receiver identity requestId (T.pack (show err))

-- | Handle streaming request
--
-- This is where SSE garbage gets converted to clean SIGIL frames:
--   1. Get SIGIL publisher from router
--   2. Create SigilBridge with model tokenizer
--   3. Create stream metadata for ZMQ topic routing
--   4. Route through provider with callback that feeds SigilBridge
--   5. SigilBridge parses SSE, tokenizes, emits SIGIL frames via PUB
--   6. Send ack via ROUTER when complete (with REAL metrics)
--
-- The client subscribes to PUB with topic "stream/<requestId>" to receive
-- clean SIGIL frames. They never see SSE or JSON.
handleStreamingRequest :: SigilReceiver -> Router -> ByteString -> Text -> Text -> ChatRequest -> IO ()
handleStreamingRequest receiver router identity requestId modelId chatReq = do
  case routerSigilPublisher router of
    Nothing -> do
      -- SIGIL publisher not configured - fall back to non-streaming
      -- This shouldn't happen in production (SIGIL should be fully enabled)
      TIO.putStrLn $ "  SIGIL publisher not available, falling back to non-streaming"
      handleNonStreamingRequest receiver router identity requestId chatReq

    Just publisher -> do
      -- Capture start time for latency calculation
      startTime <- getCurrentTime

      -- Get the model from router for tokenization
      let model = routerDefaultModel router

      -- Create bridge state for this stream
      bridgeState <- newBridgeState defaultBridgeConfig model

      -- Create stream metadata for ZMQ topic routing
      -- Clients subscribe to "stream/<requestId>" to receive frames
      meta <- newStreamMetadata requestId modelId requestId

      -- Build the bridge
      let bridge = SigilBridge
            { sbState = bridgeState,
              sbPublisher = publisher,
              sbMetadata = meta
            }

      -- Stream callback: feed each SSE chunk through SigilBridge
      -- SigilBridge parses the SSE garbage, tokenizes the content,
      -- processes through ChunkState machine, and emits SIGIL frames
      let streamCallback :: ByteString -> IO ()
          streamCallback chunk = do
            -- Process chunk through bridge (frames emitted via PUB internally)
            _ <- processSseChunk bridge chunk
            pure ()

      -- Route through streaming path
      result <- routeChatStream router requestId chatReq streamCallback

      -- Finalize bridge (flushes any remaining tokens, emits STREAM_END)
      _ <- finalizeBridge bridge

      -- Capture end time and calculate latency
      endTime <- getCurrentTime
      let latencyMs = round (diffUTCTime endTime startTime * 1000) :: Int

      -- Get metrics for percentile calculation
      metrics <- getMetrics (routerMetrics router)
      let latencyBuckets = mLatency metrics

      case result of
        Right () -> do
          TIO.putStrLn $ "  SIGIL stream complete: " <> requestId <> " (" <> T.pack (show latencyMs) <> "ms)"
          -- Send ack via ROUTER with REAL metrics - stream data already went via PUB
          sendStreamAck receiver identity requestId modelId endTime latencyMs latencyBuckets
        Left err -> do
          TIO.putStrLn $ "  SIGIL stream error: " <> requestId <> " " <> T.pack (show err)
          sendError receiver identity requestId (T.pack (show err))

-- | Send stream completion acknowledgment via ROUTER
--
-- This response confirms the stream completed successfully and includes
-- REAL metrics accumulated during the stream:
--   - Real timestamp (not fake 0)
--   - Latency in milliseconds
--   - Percentile estimates from histogram buckets
--
-- The actual content was streamed via PUB socket as SIGIL frames.
-- Usage token counts are embedded in the final SIGIL frame, but we
-- also include latency-as-completion-tokens as a proxy metric.
sendStreamAck :: SigilReceiver -> ByteString -> Text -> Text -> UTCTime -> Int -> LatencyBuckets -> IO ()
sendStreamAck receiver identity requestId modelId endTime latencyMs latencyBuckets = do
  -- Convert UTCTime to Unix timestamp (seconds since epoch)
  let unixTimestamp = floor (utcTimeToPOSIXSeconds endTime) :: Int

  -- Estimate percentiles from histogram buckets
  let p95Ms = estimatePercentile latencyBuckets 0.95 * 1000.0
      p99Ms = estimatePercentile latencyBuckets 0.99 * 1000.0

  -- Build usage with latency metrics encoded:
  --   - prompt_tokens: this request's latency in ms
  --   - completion_tokens: p95 latency in ms (rounded)
  --   - total_tokens: p99 latency in ms (rounded)
  -- This is a hack, but it lets clients see latency without JSON parsing
  let usage = Usage
        { usagePromptTokens = latencyMs,
          usageCompletionTokens = round p95Ms,
          usageTotalTokens = round p99Ms
        }

  let ackResponse = ChatResponse
        { respId = ResponseId requestId,
          respObject = "chat.completion.ack",
          respCreated = Timestamp unixTimestamp,
          respModel = ModelId modelId,
          respChoices = [],  -- Content was streamed via SIGIL frames
          respUsage = Just usage,  -- Latency metrics encoded as token counts
          respSystemFingerprint = Just $ "p95=" <> T.pack (show (round p95Ms :: Int)) <> "ms,p99=" <> T.pack (show (round p99Ms :: Int)) <> "ms"
        }
  sendResponse receiver identity requestId ackResponse

-- | Estimate latency percentile from histogram buckets
--
-- This is an approximation since we only have bucket counts.
-- Finds the first bucket that exceeds the target percentile count.
estimatePercentile :: LatencyBuckets -> Double -> Double
estimatePercentile lb percentile =
  let count = lbCount lb
      target = floor (fromIntegral count * percentile) :: Int
      -- Check buckets in order to find where target falls
      -- Buckets: 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
      buckets =
        [ (0.005, lbLe005 lb), -- <= 5ms
          (0.010, lbLe01 lb), -- <= 10ms
          (0.025, lbLe025 lb), -- <= 25ms
          (0.050, lbLe05 lb), -- <= 50ms
          (0.100, lbLe1 lb), -- <= 100ms
          (0.250, lbLe25 lb), -- <= 250ms
          (0.500, lbLe5 lb), -- <= 500ms
          (1.000, lbLe10 lb), -- <= 1s
          (2.500, lbLe25s lb), -- <= 2.5s
          (5.000, lbLe50s lb), -- <= 5s
          (10.00, lbLe100s lb) -- <= 10s
        ]
   in -- Simple estimation: find first bucket that exceeds target
      case dropWhile (\(_, c) -> fromIntegral c < target) buckets of
        [] -> 15.0 -- Fallback: > 10s, estimate at 15s
        ((latency, _) : _) -> latency
