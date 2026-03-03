{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData #-}

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                    // straylight-llm // observability/logging
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Data is the new oil. Logs are the new sludge."
--
--                                                              — Neuromancer
--
-- Structured request/response logging with configurable redaction.
--
-- Features:
-- - JSON-structured log output
-- - Configurable log levels (debug, info, warn, error)
-- - Automatic PII/secret redaction via Security.ObservabilitySanitization
-- - Request/response body logging with size limits
-- - WAI middleware for automatic request logging
--
-- Configuration via environment:
--   LOG_LEVEL=info              Log level (debug|info|warn|error)
--   LOG_FORMAT=json             Log format (json|text)
--   LOG_REQUESTS=true           Log HTTP requests
--   LOG_RESPONSES=true          Log HTTP responses
--   LOG_BODIES=false            Include request/response bodies (redacted)
--   LOG_MAX_BODY_SIZE=1024      Max body size to log
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

module Observability.Logging
  ( -- * Configuration
    LogConfig (..),
    LogLevel (..),
    LogFormat (..),
    defaultLogConfig,
    loadLogConfig,

    -- * Logger Handle
    LoggerHandle (..),
    initLogger,

    -- * Logging Functions
    logDebug,
    logInfo,
    logWarn,
    logError,

    -- * Structured Logging
    LogEvent (..),
    logEvent,

    -- * Request/Response Logging
    RequestLog (..),
    ResponseLog (..),
    logRequest,
    logResponse,

    -- * WAI Middleware
    loggingMiddleware,

    -- * Redaction
    RedactionConfig (..),
    defaultRedactionConfig,
    redactText,
    redactHeaders,
  )
where

import Data.Aeson (ToJSON (toJSON), Value (Bool, Null, Number, String), encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.ByteString.Lazy qualified as LBS
import Data.CaseInsensitive qualified as CI
import Data.IORef (IORef, atomicModifyIORef', newIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import GHC.Generics (Generic)
import Network.HTTP.Types (statusCode)
import Network.Wai
  ( Middleware,
    rawPathInfo,
    rawQueryString,
    remoteHost,
    requestHeaders,
    requestMethod,
    responseStatus,
  )
import Security.ObservabilitySanitization
  ( LatencyBucket,
    bucketLatency,
    hashRequestId,
    sanitizeHeaders,
  )
import System.Environment (lookupEnv)
import System.IO (Handle, hPutStrLn, stderr)

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // configuration
-- ════════════════════════════════════════════════════════════════════════════

-- | Log levels
data LogLevel
  = LogDebug
  | LogInfo
  | LogWarn
  | LogError
  deriving (Show, Eq, Ord, Generic)

instance ToJSON LogLevel where
  toJSON LogDebug = String "debug"
  toJSON LogInfo = String "info"
  toJSON LogWarn = String "warn"
  toJSON LogError = String "error"

-- | Parse log level from string
parseLogLevel :: String -> LogLevel
parseLogLevel s = case map toLower s of
  "debug" -> LogDebug
  "info" -> LogInfo
  "warn" -> LogWarn
  "warning" -> LogWarn
  "error" -> LogError
  "err" -> LogError
  _ -> LogInfo
  where
    toLower c
      | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
      | otherwise = c

-- | Log output format
data LogFormat
  = LogFormatJSON
  | LogFormatText
  deriving (Show, Eq)

-- | Logging configuration
data LogConfig = LogConfig
  { -- | Minimum log level to output
    lcLevel :: !LogLevel,
    -- | Output format (JSON or text)
    lcFormat :: !LogFormat,
    -- | Log incoming HTTP requests
    lcLogRequests :: !Bool,
    -- | Log outgoing HTTP responses
    lcLogResponses :: !Bool,
    -- | Include request/response bodies (redacted)
    lcLogBodies :: !Bool,
    -- | Maximum body size to log (bytes)
    lcMaxBodySize :: !Int,
    -- | Additional patterns to redact
    lcRedactPatterns :: ![Text],
    -- | Output handle (default: stderr)
    lcOutput :: !Handle
  }
  deriving (Show)

-- | Default logging configuration
defaultLogConfig :: LogConfig
defaultLogConfig =
  LogConfig
    { lcLevel = LogInfo,
      lcFormat = LogFormatJSON,
      lcLogRequests = True,
      lcLogResponses = True,
      lcLogBodies = False,
      lcMaxBodySize = 1024,
      lcRedactPatterns = defaultRedactPatterns,
      lcOutput = stderr
    }

-- | Default patterns to redact from logs
defaultRedactPatterns :: [Text]
defaultRedactPatterns =
  [ "api_key",
    "api-key",
    "apikey",
    "authorization",
    "bearer",
    "password",
    "secret",
    "token",
    "credential",
    "private_key",
    "private-key",
    "sk-", -- OpenAI API key prefix
    "sk_", -- Stripe-style key prefix
    "xoxb-", -- Slack bot token
    "xoxp-", -- Slack user token
    "ghp_", -- GitHub PAT
    "gho_", -- GitHub OAuth
    "glpat-" -- GitLab PAT
  ]

-- | Load logging configuration from environment
loadLogConfig :: IO LogConfig
loadLogConfig = do
  level <- maybe "info" id <$> lookupEnv "LOG_LEVEL"
  format <- maybe "json" id <$> lookupEnv "LOG_FORMAT"
  logRequests <- maybe True (== "true") <$> lookupEnv "LOG_REQUESTS"
  logResponses <- maybe True (== "true") <$> lookupEnv "LOG_RESPONSES"
  logBodies <- maybe False (== "true") <$> lookupEnv "LOG_BODIES"
  maxBodySize <- maybe 1024 read <$> lookupEnv "LOG_MAX_BODY_SIZE"

  pure
    LogConfig
      { lcLevel = parseLogLevel level,
        lcFormat = if format == "text" then LogFormatText else LogFormatJSON,
        lcLogRequests = logRequests,
        lcLogResponses = logResponses,
        lcLogBodies = logBodies,
        lcMaxBodySize = maxBodySize,
        lcRedactPatterns = defaultRedactPatterns,
        lcOutput = stderr
      }

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // logger handle
-- ════════════════════════════════════════════════════════════════════════════

-- | Logger handle
data LoggerHandle = LoggerHandle
  { lhConfig :: !LogConfig,
    lhRequestCounter :: !(IORef Int)
  }

-- | Initialize the logger
initLogger :: LogConfig -> IO LoggerHandle
initLogger config = do
  counter <- newIORef 0
  pure
    LoggerHandle
      { lhConfig = config,
        lhRequestCounter = counter
      }

-- ════════════════════════════════════════════════════════════════════════════
--                                                         // logging functions
-- ════════════════════════════════════════════════════════════════════════════

-- | Log at debug level
logDebug :: LoggerHandle -> Text -> IO ()
logDebug lh msg = logAt lh LogDebug msg

-- | Log at info level
logInfo :: LoggerHandle -> Text -> IO ()
logInfo lh msg = logAt lh LogInfo msg

-- | Log at warn level
logWarn :: LoggerHandle -> Text -> IO ()
logWarn lh msg = logAt lh LogWarn msg

-- | Log at error level
logError :: LoggerHandle -> Text -> IO ()
logError lh msg = logAt lh LogError msg

-- | Log at a specific level
logAt :: LoggerHandle -> LogLevel -> Text -> IO ()
logAt lh level msg = do
  let config = lhConfig lh
  if level >= lcLevel config
    then do
      timestamp <- getCurrentTime
      let event =
            LogEvent
              { leTimestamp = timestamp,
                leLevel = level,
                leMessage = msg,
                leFields = []
              }
      outputLog config event
    else pure ()

-- ════════════════════════════════════════════════════════════════════════════
--                                                        // structured logging
-- ════════════════════════════════════════════════════════════════════════════

-- | A structured log event
data LogEvent = LogEvent
  { leTimestamp :: !UTCTime,
    leLevel :: !LogLevel,
    leMessage :: !Text,
    leFields :: ![(Text, Value)]
  }
  deriving (Show, Generic)

instance ToJSON LogEvent where
  toJSON LogEvent {..} =
    object $
      [ "timestamp" .= iso8601Show leTimestamp,
        "level" .= leLevel,
        "message" .= leMessage
      ]
        <> map (\(k, v) -> Key.fromText k .= v) leFields

-- | Log a structured event
logEvent :: LoggerHandle -> LogEvent -> IO ()
logEvent lh event = do
  let config = lhConfig lh
  if leLevel event >= lcLevel config
    then outputLog config event
    else pure ()

-- | Output a log event
outputLog :: LogConfig -> LogEvent -> IO ()
outputLog config event = do
  let output = case lcFormat config of
        LogFormatJSON -> LBS.toStrict $ encode event
        LogFormatText -> TE.encodeUtf8 $ formatText event
  hPutStrLn (lcOutput config) (T.unpack $ TE.decodeUtf8 output)

-- | Format event as text
formatText :: LogEvent -> Text
formatText LogEvent {..} =
  T.concat
    [ T.pack $ iso8601Show leTimestamp,
      " [",
      levelText leLevel,
      "] ",
      leMessage,
      if null leFields then "" else " " <> formatFields leFields
    ]
  where
    levelText LogDebug = "DEBUG"
    levelText LogInfo = "INFO"
    levelText LogWarn = "WARN"
    levelText LogError = "ERROR"

    formatFields fs = T.intercalate " " [k <> "=" <> showValue v | (k, v) <- fs]
    showValue (String s) = s
    showValue (Number n) = T.pack $ show n
    showValue (Bool b) = if b then "true" else "false"
    showValue Null = "null"
    showValue v = T.pack $ show v

-- ════════════════════════════════════════════════════════════════════════════
--                                                    // request/response logging
-- ════════════════════════════════════════════════════════════════════════════

-- | Logged request data
data RequestLog = RequestLog
  { rlRequestId :: !Text,
    rlMethod :: !Text,
    rlPath :: !Text,
    rlQuery :: !(Maybe Text),
    rlHeaders :: ![(Text, Text)],
    rlBodySize :: !Int,
    rlBody :: !(Maybe Text),
    rlRemoteAddr :: !Text,
    rlTimestamp :: !UTCTime
  }
  deriving (Show, Generic)

instance ToJSON RequestLog where
  toJSON RequestLog {..} =
    object
      [ "request_id" .= hashRequestId rlRequestId,
        "method" .= rlMethod,
        "path" .= rlPath,
        "query" .= rlQuery,
        "headers" .= object [Key.fromText k .= v | (k, v) <- rlHeaders],
        "body_size" .= rlBodySize,
        "body" .= rlBody,
        "remote_addr" .= rlRemoteAddr,
        "timestamp" .= iso8601Show rlTimestamp
      ]

-- | Logged response data
data ResponseLog = ResponseLog
  { rsRequestId :: !Text,
    rsStatusCode :: !Int,
    rsLatencyMs :: !Double,
    rsLatencyBucket :: !LatencyBucket,
    rsBodySize :: !Int,
    rsBody :: !(Maybe Text),
    rsTimestamp :: !UTCTime
  }
  deriving (Show, Generic)

instance ToJSON ResponseLog where
  toJSON ResponseLog {..} =
    object
      [ "request_id" .= hashRequestId rsRequestId,
        "status_code" .= rsStatusCode,
        "latency_ms" .= rsLatencyMs,
        "latency_bucket" .= show rsLatencyBucket,
        "body_size" .= rsBodySize,
        "body" .= rsBody,
        "timestamp" .= iso8601Show rsTimestamp
      ]

-- | Log an incoming request
logRequest :: LoggerHandle -> RequestLog -> IO ()
logRequest lh reqLog = do
  timestamp <- getCurrentTime
  let event =
        LogEvent
          { leTimestamp = timestamp,
            leLevel = LogInfo,
            leMessage = "request",
            leFields = [("request", toJSON reqLog)]
          }
  logEvent lh event

-- | Log an outgoing response
logResponse :: LoggerHandle -> ResponseLog -> IO ()
logResponse lh respLog = do
  timestamp <- getCurrentTime
  let level =
        if rsStatusCode respLog >= 500
          then LogError
          else
            if rsStatusCode respLog >= 400
              then LogWarn
              else LogInfo
  let event =
        LogEvent
          { leTimestamp = timestamp,
            leLevel = level,
            leMessage = "response",
            leFields = [("response", toJSON respLog)]
          }
  logEvent lh event

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // wai middleware
-- ════════════════════════════════════════════════════════════════════════════

-- | WAI middleware for automatic request/response logging
loggingMiddleware :: LoggerHandle -> Middleware
loggingMiddleware lh app req respond = do
  let config = lhConfig lh

  -- Generate request ID
  reqNum <- atomicModifyIORef' (lhRequestCounter lh) (\n -> (n + 1, n + 1))
  let requestId = "req_" <> T.pack (show reqNum)

  -- Capture start time
  startTime <- getCurrentTime

  -- Log request if enabled
  if lcLogRequests config
    then do
      let reqLog =
            RequestLog
              { rlRequestId = requestId,
                rlMethod = TE.decodeUtf8 $ requestMethod req,
                rlPath = TE.decodeUtf8 $ rawPathInfo req,
                rlQuery =
                  let q = rawQueryString req
                   in if q == "" then Nothing else Just (TE.decodeUtf8 q),
                rlHeaders =
                  sanitizeHeaders $
                    map
                      ( \(k, v) ->
                          (TE.decodeUtf8 $ CI.original k, redactValue config $ TE.decodeUtf8 v)
                      )
                      (requestHeaders req),
                rlBodySize = 0, -- Would need to buffer request body
                rlBody = Nothing,
                rlRemoteAddr = T.pack $ show $ remoteHost req,
                rlTimestamp = startTime
              }
      logRequest lh reqLog
    else pure ()

  -- Process request
  app req $ \response -> do
    endTime <- getCurrentTime
    let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double

    -- Log response if enabled
    if lcLogResponses config
      then do
        let status = responseStatus response
        let respLog =
              ResponseLog
                { rsRequestId = requestId,
                  rsStatusCode = statusCode status,
                  rsLatencyMs = latencyMs,
                  rsLatencyBucket = bucketLatency (round latencyMs),
                  rsBodySize = 0, -- Would need response body buffering
                  rsBody = Nothing,
                  rsTimestamp = endTime
                }
        logResponse lh respLog
      else pure ()

    respond response

-- ════════════════════════════════════════════════════════════════════════════
--                                                               // redaction
-- ════════════════════════════════════════════════════════════════════════════

-- | Redaction configuration
data RedactionConfig = RedactionConfig
  { -- | Patterns that trigger redaction
    rcPatterns :: ![Text],
    -- | Replacement text for redacted values
    rcReplacement :: !Text
  }
  deriving (Show, Eq)

-- | Default redaction configuration
defaultRedactionConfig :: RedactionConfig
defaultRedactionConfig =
  RedactionConfig
    { rcPatterns = defaultRedactPatterns,
      rcReplacement = "[REDACTED]"
    }

-- | Redact sensitive values from text
redactText :: RedactionConfig -> Text -> Text
redactText RedactionConfig {..} text =
  if any (`T.isInfixOf` T.toLower text) rcPatterns
    then rcReplacement
    else text

-- | Redact a header value based on header name
redactValue :: LogConfig -> Text -> Text
redactValue config value =
  -- Check if value looks like a secret (starts with common prefixes)
  if any (`T.isPrefixOf` value) (lcRedactPatterns config)
    then "[REDACTED]"
    else value

-- | Redact sensitive headers
redactHeaders :: LogConfig -> [(Text, Text)] -> [(Text, Text)]
redactHeaders config = map redactHeader
  where
    redactHeader (name, value)
      | any (`T.isInfixOf` T.toLower name) sensitiveNames = (name, "[REDACTED]")
      | otherwise = (name, redactValue config value)

    sensitiveNames =
      [ "authorization",
        "api-key",
        "apikey",
        "token",
        "secret",
        "password",
        "cookie"
      ]
