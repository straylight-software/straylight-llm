{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData #-}

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                    // straylight-llm // observability/tracing
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Night City was like a deranged experiment in social Darwinism,
--      designed by a bored researcher who kept one thumb permanently
--      on the fast-forward button."
--
--                                                              — Neuromancer
--
-- OpenTelemetry distributed tracing for the gateway.
--
-- Provides:
-- - TracerProvider initialization (OTLP exporter or noop)
-- - Span helpers for tracing provider calls
-- - WAI middleware for automatic request tracing
-- - Context propagation (W3C Trace Context)
--
-- Configuration via environment:
--   OTEL_ENABLED=true           Enable tracing (default: false)
--   OTEL_EXPORTER_OTLP_ENDPOINT OTLP endpoint (default: http://localhost:4317)
--   OTEL_SERVICE_NAME           Service name (default: straylight-llm)
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

module Observability.Tracing
  ( -- * Tracer Provider
    TracingConfig (..),
    defaultTracingConfig,
    loadTracingConfig,

    -- * Tracer Handle
    TracerHandle (..),
    initTracer,
    shutdownTracer,
    withTracer,

    -- * Span Operations
    withSpan,
    withSpan_,
    addAttribute,
    addAttributes,
    recordException,
    setStatus,

    -- * Provider Tracing
    traceProviderCall,

    -- * WAI Middleware
    tracingMiddleware,

    -- * Span Attributes (semantic conventions)
    SpanKind (..),
    SpanStatus (..),

    -- * Span Context (for testing)
    SpanContext (..),
  )
where

import Control.Exception (SomeException, bracket, try)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import Data.Word (Word64)
import Network.HTTP.Types (statusCode)
import Network.Wai (Middleware, rawPathInfo, requestMethod, responseStatus)
import Numeric (showHex)
import System.Environment (lookupEnv)
import System.Random (randomIO)

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // configuration
-- ════════════════════════════════════════════════════════════════════════════

-- | Tracing configuration
data TracingConfig = TracingConfig
  { -- | Whether tracing is enabled
    tcEnabled :: !Bool,
    -- | OTLP gRPC endpoint (e.g., "http://localhost:4317")
    tcOtlpEndpoint :: !Text,
    -- | Service name for spans
    tcServiceName :: !Text,
    -- | Service version
    tcServiceVersion :: !Text,
    -- | Sampling rate (0.0 to 1.0, default 1.0 = sample everything)
    tcSampleRate :: !Double
  }
  deriving (Show, Eq)

-- | Default tracing configuration (disabled)
defaultTracingConfig :: TracingConfig
defaultTracingConfig =
  TracingConfig
    { tcEnabled = False,
      tcOtlpEndpoint = "http://localhost:4317",
      tcServiceName = "straylight-llm",
      tcServiceVersion = "0.1.0",
      tcSampleRate = 1.0
    }

-- | Load tracing configuration from environment
loadTracingConfig :: IO TracingConfig
loadTracingConfig = do
  enabled <- maybe False (== "true") <$> lookupEnv "OTEL_ENABLED"
  endpoint <- maybe "http://localhost:4317" T.pack <$> lookupEnv "OTEL_EXPORTER_OTLP_ENDPOINT"
  serviceName <- maybe "straylight-llm" T.pack <$> lookupEnv "OTEL_SERVICE_NAME"
  serviceVersion <- maybe "0.1.0" T.pack <$> lookupEnv "OTEL_SERVICE_VERSION"
  sampleRate <- maybe 1.0 read <$> lookupEnv "OTEL_SAMPLE_RATE"

  pure
    TracingConfig
      { tcEnabled = enabled,
        tcOtlpEndpoint = endpoint,
        tcServiceName = serviceName,
        tcServiceVersion = serviceVersion,
        tcSampleRate = sampleRate
      }

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // tracer handle
-- ════════════════════════════════════════════════════════════════════════════

-- | Span kind (OpenTelemetry semantic convention)
data SpanKind
  = SpanKindInternal
  | SpanKindServer
  | SpanKindClient
  | SpanKindProducer
  | SpanKindConsumer
  deriving (Show, Eq)

-- | Span status
data SpanStatus
  = StatusUnset
  | StatusOk
  | StatusError !Text
  deriving (Show, Eq)

-- | A span context (simplified - real impl would use OTel types)
data SpanContext = SpanContext
  { scTraceId :: !Text,
    scSpanId :: !Text,
    scParentSpanId :: !(Maybe Text),
    scSampled :: !Bool
  }
  deriving (Show, Eq)

-- | An active span
data Span = Span
  { spanContext :: !SpanContext,
    spanName :: !Text,
    spanKind :: !SpanKind,
    spanStartTime :: !UTCTime,
    spanAttributes :: !(IORef [(Text, Text)]),
    spanStatus :: !(IORef SpanStatus)
  }

-- | Tracer handle - holds the tracer provider state
data TracerHandle = TracerHandle
  { thConfig :: !TracingConfig,
    thCurrentSpan :: !(IORef (Maybe Span)),
    -- | Function to export completed spans
    thSpanExporter :: !(Span -> UTCTime -> IO ())
  }

-- | Initialize the tracer
initTracer :: TracingConfig -> IO TracerHandle
initTracer config = do
  currentSpan <- newIORef Nothing

  -- Create exporter based on config
  let exporter =
        if tcEnabled config
          then otlpExporter config
          else noopExporter

  pure
    TracerHandle
      { thConfig = config,
        thCurrentSpan = currentSpan,
        thSpanExporter = exporter
      }

-- | Shutdown the tracer (flush pending spans)
shutdownTracer :: TracerHandle -> IO ()
shutdownTracer _th = do
  -- In a real implementation, this would:
  -- 1. Flush any pending spans
  -- 2. Shutdown the OTLP exporter
  -- 3. Wait for graceful shutdown
  pure ()

-- | Bracket-style tracer initialization
withTracer :: TracingConfig -> (TracerHandle -> IO a) -> IO a
withTracer config = bracket (initTracer config) shutdownTracer

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // span operations
-- ════════════════════════════════════════════════════════════════════════════

-- | Execute an action within a span
withSpan :: TracerHandle -> Text -> SpanKind -> IO a -> IO (a, SpanContext)
withSpan th name kind action = do
  if not (tcEnabled (thConfig th))
    then do
      result <- action
      pure (result, emptyContext)
    else do
      -- Generate trace/span IDs
      traceId <- generateTraceId
      spanId <- generateSpanId

      -- Get parent span if any
      mParent <- readIORef (thCurrentSpan th)
      let parentId = spanContext <$> mParent
          ctx =
            SpanContext
              { scTraceId = maybe traceId scTraceId parentId,
                scSpanId = spanId,
                scParentSpanId = scSpanId <$> parentId,
                scSampled = True
              }

      -- Create span
      startTime <- getCurrentTime
      attrs <- newIORef []
      status <- newIORef StatusUnset

      let sp =
            Span
              { spanContext = ctx,
                spanName = name,
                spanKind = kind,
                spanStartTime = startTime,
                spanAttributes = attrs,
                spanStatus = status
              }

      -- Set as current span
      writeIORef (thCurrentSpan th) (Just sp)

      -- Run action
      result <- try action

      -- End span
      endTime <- getCurrentTime

      -- Restore parent span
      writeIORef (thCurrentSpan th) mParent

      case result of
        Left (e :: SomeException) -> do
          writeIORef status (StatusError (T.pack $ show e))
          thSpanExporter th sp endTime
          -- Re-throw
          fail $ show e
        Right a -> do
          thSpanExporter th sp endTime
          pure (a, ctx)

-- | Execute an action within a span (discarding context)
withSpan_ :: TracerHandle -> Text -> SpanKind -> IO a -> IO a
withSpan_ th name kind action = fst <$> withSpan th name kind action

-- | Add a single attribute to the current span
addAttribute :: TracerHandle -> Text -> Text -> IO ()
addAttribute th key value = do
  mSpan <- readIORef (thCurrentSpan th)
  case mSpan of
    Nothing -> pure ()
    Just sp -> do
      attrs <- readIORef (spanAttributes sp)
      writeIORef (spanAttributes sp) ((key, value) : attrs)

-- | Add multiple attributes to the current span
addAttributes :: TracerHandle -> [(Text, Text)] -> IO ()
addAttributes th attrs = mapM_ (uncurry $ addAttribute th) attrs

-- | Record an exception in the current span
recordException :: TracerHandle -> SomeException -> IO ()
recordException th e = do
  addAttribute th "exception.type" "SomeException"
  addAttribute th "exception.message" (T.pack $ show e)
  setStatus th (StatusError (T.pack $ show e))

-- | Set the span status
setStatus :: TracerHandle -> SpanStatus -> IO ()
setStatus th st = do
  mSpan <- readIORef (thCurrentSpan th)
  case mSpan of
    Nothing -> pure ()
    Just sp -> writeIORef (spanStatus sp) st

-- ════════════════════════════════════════════════════════════════════════════
--                                                         // provider tracing
-- ════════════════════════════════════════════════════════════════════════════

-- | Trace a provider call with semantic attributes
traceProviderCall ::
  TracerHandle ->
  -- | Provider name
  Text ->
  -- | Model name
  Text ->
  -- | Operation (chat, embeddings, models)
  Text ->
  -- | Action to trace
  IO a ->
  IO a
traceProviderCall th provider model operation action = do
  withSpan_ th ("provider." <> operation) SpanKindClient $ do
    addAttributes
      th
      [ ("llm.provider", provider),
        ("llm.model", model),
        ("llm.operation", operation)
      ]
    action

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // wai middleware
-- ════════════════════════════════════════════════════════════════════════════

-- | WAI middleware for automatic request tracing
tracingMiddleware :: TracerHandle -> Middleware
tracingMiddleware th app req respond = do
  if not (tcEnabled (thConfig th))
    then app req respond
    else do
      let path = TE.decodeUtf8 $ rawPathInfo req
          method = TE.decodeUtf8 $ requestMethod req
          spanName = method <> " " <> path

      withSpan_ th spanName SpanKindServer $ do
        -- Add HTTP semantic convention attributes
        addAttributes
          th
          [ ("http.method", method),
            ("http.target", path),
            ("http.scheme", "http") -- TODO: detect from request
          ]

        -- Call the application
        app req $ \response -> do
          -- Add response attributes
          let status = responseStatus response
          addAttribute th "http.status_code" (T.pack $ show $ statusCode status)

          -- Set span status based on HTTP status
          when (statusCode status >= 500) $
            setStatus th (StatusError "Server error")
          when (statusCode status >= 400 && statusCode status < 500) $
            setStatus th (StatusError "Client error")

          respond response
  where
    when True action = action
    when False _ = pure ()

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // exporters
-- ════════════════════════════════════════════════════════════════════════════

-- | OTLP exporter (logs to stderr for now - real impl would use gRPC)
otlpExporter :: TracingConfig -> Span -> UTCTime -> IO ()
otlpExporter _config sp endTime = do
  attrs <- readIORef (spanAttributes sp)
  st <- readIORef (spanStatus sp)
  let duration = diffUTCTime endTime (spanStartTime sp)
      ctx = spanContext sp

  -- Log span to stderr (structured format)
  -- In production, this would send to OTLP collector via gRPC
  putStrLn $
    concat
      [ "[SPAN] ",
        "trace_id=",
        T.unpack (scTraceId ctx),
        " span_id=",
        T.unpack (scSpanId ctx),
        maybe "" (\p -> " parent_id=" <> T.unpack p) (scParentSpanId ctx),
        " name=",
        T.unpack (spanName sp),
        " duration_ms=",
        show (realToFrac duration * 1000 :: Double),
        " status=",
        show st,
        " attrs=",
        show attrs
      ]

-- | Noop exporter (does nothing)
noopExporter :: Span -> UTCTime -> IO ()
noopExporter _ _ = pure ()

-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Empty span context for when tracing is disabled
emptyContext :: SpanContext
emptyContext =
  SpanContext
    { scTraceId = "",
      scSpanId = "",
      scParentSpanId = Nothing,
      scSampled = False
    }

-- | Generate a trace ID (128-bit hex)
generateTraceId :: IO Text
generateTraceId = do
  -- Generate 128 bits (16 bytes) as two Word64s
  w1 <- randomIO :: IO Word64
  w2 <- randomIO :: IO Word64
  pure $ T.pack $ padHex 16 w1 <> padHex 16 w2

-- | Generate a span ID (64-bit hex)
generateSpanId :: IO Text
generateSpanId = do
  w <- randomIO :: IO Word64
  pure $ T.pack $ padHex 16 w

-- | Pad hex string to specified length
padHex :: Int -> Word64 -> String
padHex n w =
  let hex = showHex w ""
   in replicate (n - length hex) '0' <> hex
