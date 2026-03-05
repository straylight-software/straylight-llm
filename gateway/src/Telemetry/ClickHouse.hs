-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                       // straylight-llm // telemetry/clickhouse
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The matrix has its roots in primitive arcade games... in early
--      graphics programs and military experimentation with cranial jacks."
--
--                                                              — Neuromancer
--
-- ClickHouse integration for metrics persistence.
-- Sends request logs and metric snapshots to ClickHouse for dashboarding.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Telemetry.ClickHouse
  ( -- * Configuration
    ClickHouseConfig (..),
    defaultClickHouseConfig,

    -- * Client
    ClickHouseClient,
    newClickHouseClient,

    -- * Operations
    insertRequest,
    insertMetricsSnapshot,
    insertProviderMetrics,

    -- * Background Flusher
    startMetricsFlusher,
  )
where

import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Exception (SomeException, catch)
import Control.Monad (forever, when)
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (UTCTime, getCurrentTime)
import Data.Time.Format (formatTime, defaultTimeLocale)
import Data.Word (Word64)
import Network.HTTP.Client
  ( Manager,
    RequestBody (RequestBodyLBS),
    httpLbs,
    method,
    parseRequest,
    requestBody,
    requestHeaders,
    responseBody,
    responseStatus,
  )
import Network.HTTP.Types (Header, status200)
import Resilience.Metrics (Metrics (..), MetricsStore, ProviderMetrics (..), getMetrics, LatencyBuckets(..))
import Provider.Types (ProviderName)
import Data.Map.Strict qualified as Map

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // config
-- ════════════════════════════════════════════════════════════════════════════

-- | ClickHouse connection configuration
data ClickHouseConfig = ClickHouseConfig
  { chHost :: Text,           -- ^ Hostname (e.g., "localhost" or "xyz.clickhouse.cloud")
    chPort :: Int,            -- ^ Port (8123 for HTTP, 8443 for HTTPS)
    chDatabase :: Text,       -- ^ Database name
    chUser :: Maybe Text,     -- ^ Username (Nothing for default)
    chPassword :: Maybe Text, -- ^ Password (Nothing for no auth)
    chUseTLS :: Bool,         -- ^ Use HTTPS?
    chEnabled :: Bool         -- ^ Is ClickHouse integration enabled?
  }
  deriving (Eq, Show)

-- | Default configuration for local development
-- 
-- Connects to localhost:8123 with no authentication.
-- Override via environment variables in production.
defaultClickHouseConfig :: ClickHouseConfig
defaultClickHouseConfig =
  ClickHouseConfig
    { chHost = "localhost",
      chPort = 8123,
      chDatabase = "straylight",
      chUser = Nothing,
      chPassword = Nothing,
      chUseTLS = False,
      chEnabled = True
    }

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // client
-- ════════════════════════════════════════════════════════════════════════════

-- | ClickHouse client handle
data ClickHouseClient = ClickHouseClient
  { chcConfig :: ClickHouseConfig,
    chcManager :: Manager,
    chcBaseUrl :: Text
  }

-- | Create a new ClickHouse client
--
-- Takes an HTTP Manager (for connection pooling) and config.
newClickHouseClient :: Manager -> ClickHouseConfig -> ClickHouseClient
newClickHouseClient manager config =
  ClickHouseClient
    { chcConfig = config,
      chcManager = manager,
      chcBaseUrl = buildBaseUrl config
    }

-- | Build the base URL from config
--
-- Examples:
--   - Local: "http://localhost:8123"
--   - Cloud: "https://xyz.clickhouse.cloud:8443"
buildBaseUrl :: ClickHouseConfig -> Text
buildBaseUrl ClickHouseConfig {..} =
  let protocol = if chUseTLS then "https" else "http"
   in {- YOUR CODE HERE: Build the URL string -}
      -- Hint: Combine protocol, host, and port into a URL
      -- Example output: "http://localhost:8123"
      protocol <> "://" <> chHost <> ":" <> T.pack (show chPort)

-- ════════════════════════════════════════════════════════════════════════════
--                                                               // operations
-- ════════════════════════════════════════════════════════════════════════════

-- | A single request record to insert
data RequestRecord = RequestRecord
  { rrTimestamp :: UTCTime,
    rrRequestId :: Text,
    rrModel :: Text,
    rrProvider :: Text,
    rrLatencyMs :: Double,
    rrTtftMs :: Double,
    rrStatus :: Text,          -- "success" | "error"
    rrErrorType :: Maybe Text, -- "auth" | "rate_limit" | "timeout" | etc.
    rrTokensPrompt :: Word64,
    rrTokensCompletion :: Word64,
    rrCached :: Bool
  }
  deriving (Eq, Show)

-- | Insert a request record into ClickHouse
--
-- Sends an HTTP POST to ClickHouse with the INSERT query.
insertRequest :: ClickHouseClient -> RequestRecord -> IO (Either Text ())
insertRequest client RequestRecord {..} = do
  let sql = T.unlines
        [ "INSERT INTO requests"
        , "(timestamp, request_id, model, provider, latency_ms, ttft_ms, status, error_type, tokens_prompt, tokens_completion, cached)"
        , "VALUES"
        , "(" <> T.intercalate ", "
            [ formatTimestamp rrTimestamp
            , quote rrRequestId
            , quote rrModel
            , quote rrProvider
            , T.pack (show rrLatencyMs)
            , T.pack (show rrTtftMs)
            , quote rrStatus
            , {- YOUR CODE HERE: Format the Maybe error_type -}
              -- Hint: NULL for Nothing, quoted string for Just
              -- Use the `formatMaybeText` helper below
              formatMaybeText rrErrorType
            , T.pack (show rrTokensPrompt)
            , T.pack (show rrTokensCompletion)
            , if rrCached then "true" else "false"
            ]
        <> ")"
        ]
  executeQuery client sql

-- | Insert a metrics snapshot
insertMetricsSnapshot :: ClickHouseClient -> Metrics -> IO (Either Text ())
insertMetricsSnapshot client Metrics {..} = do
  now <- getCurrentTime
  let -- Calculate percentiles from histogram buckets
      (p50, p95, p99) = calculatePercentiles mLatency
      -- Calculate error rate
      totalErrors = sum [pmErrorsAuth pm + pmErrorsRateLimit pm + pmErrorsTimeout pm + pmErrorsUnavailable pm + pmErrorsOther pm | pm <- Map.elems mProviders]
      totalRequests = mRequestsTotal
      errorRate :: Double
      errorRate = if totalRequests == 0 then 0.0 else fromIntegral totalErrors / fromIntegral totalRequests

      sql = T.unlines
        [ "INSERT INTO metrics_snapshots"
        , "(timestamp, requests_total, requests_active, latency_p50_ms, latency_p95_ms, latency_p99_ms, error_rate)"
        , "VALUES"
        , "(" <> T.intercalate ", "
            [ formatTimestamp now
            , {- YOUR CODE HERE: Format requests_total as Text -}
              -- Hint: Use T.pack and show
              T.pack (show mRequestsTotal)
            , T.pack (show mRequestsActive)
            , T.pack (show p50)
            , T.pack (show p95)
            , T.pack (show p99)
            , T.pack (show errorRate)
            ]
        <> ")"
        ]
  executeQuery client sql

-- | Insert per-provider metrics
insertProviderMetrics :: ClickHouseClient -> ProviderName -> ProviderMetrics -> IO (Either Text ())
insertProviderMetrics client provider ProviderMetrics {..} = do
  now <- getCurrentTime
  let avgLatency = if lbCount pmLatency == 0 then 0.0 else (lbSum pmLatency / fromIntegral (lbCount pmLatency)) * 1000.0
      avgTtft = if lbCount pmTTFT == 0 then 0.0 else (lbSum pmTTFT / fromIntegral (lbCount pmTTFT)) * 1000.0

      sql = T.unlines
        [ "INSERT INTO provider_metrics"
        , "(timestamp, provider, requests_total, errors_auth, errors_rate_limit, errors_timeout, errors_unavailable, errors_other, avg_latency_ms, avg_ttft_ms)"
        , "VALUES"
        , "(" <> T.intercalate ", "
            [ formatTimestamp now
            , quote (T.toLower $ T.pack $ show provider)
            , T.pack (show pmRequestsTotal)
            , {- YOUR CODE HERE: Format the 5 error counts -}
              -- Hint: Each one needs T.pack (show pmErrorsXxx)
              T.pack (show pmErrorsAuth)
            , T.pack (show pmErrorsRateLimit)
            , T.pack (show pmErrorsTimeout)
            , T.pack (show pmErrorsUnavailable)
            , T.pack (show pmErrorsOther)
            , T.pack (show avgLatency)
            , T.pack (show avgTtft)
            ]
        <> ")"
        ]
  executeQuery client sql

-- ════════════════════════════════════════════════════════════════════════════
--                                                        // background flusher
-- ════════════════════════════════════════════════════════════════════════════

-- | Start a background thread that periodically flushes metrics to ClickHouse
--
-- Runs every 10 seconds, inserting:
--   1. A metrics snapshot (global stats)
--   2. Per-provider metrics for each active provider
startMetricsFlusher :: ClickHouseClient -> MetricsStore -> IO ThreadId
startMetricsFlusher client metricsStore = do
  putStrLn $ "[ClickHouse] Starting metrics flusher -> " <> T.unpack (chcBaseUrl client)
  forkIO $ forever $ do
    -- Wait 10 seconds between flushes
    threadDelay (10 * 1000000)

    -- Only flush if enabled
    when (chEnabled (chcConfig client)) $ do
      -- Get current metrics
      metrics <- getMetrics metricsStore

      -- Insert global snapshot
      result1 <- insertMetricsSnapshot client metrics
      case result1 of
        Left err -> putStrLn $ "[ClickHouse] Snapshot insert failed: " <> T.unpack err
        Right () -> putStrLn "[ClickHouse] Metrics snapshot inserted"

      -- Insert per-provider metrics
      {- YOUR CODE HERE: Loop through mProviders and insert each one -}
      -- Hint: Use Map.toList to get [(ProviderName, ProviderMetrics)]
      -- Then use mapM_ to call insertProviderMetrics for each
      mapM_ (\(pName, pMetrics) -> do
          result <- insertProviderMetrics client pName pMetrics
          case result of
            Left err -> putStrLn $ "[ClickHouse] Provider metrics insert failed: " <> T.unpack err
            Right () -> pure ()
        ) (Map.toList (mProviders metrics))

-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Execute a query against ClickHouse
executeQuery :: ClickHouseClient -> Text -> IO (Either Text ())
executeQuery ClickHouseClient {..} sql = do
  let url = T.unpack chcBaseUrl <> "/?database=" <> T.unpack (chDatabase chcConfig)

  result <- (do
    baseRequest <- parseRequest url
    let request = baseRequest
          { method = "POST"
          , requestBody = RequestBodyLBS (LBS.fromStrict (TE.encodeUtf8 sql))
          , requestHeaders = buildAuthHeaders chcConfig
          }
    response <- httpLbs request chcManager
    if responseStatus response == status200
      then pure (Right ())
      else do
        -- Get the response body for debugging
        let body = TE.decodeUtf8 (LBS.toStrict (responseBody response))
        pure (Left $ "HTTP " <> T.pack (show (responseStatus response)) <> ": " <> T.take 200 body)
    ) `catch` \(e :: SomeException) ->
        pure (Left $ "Exception: " <> T.pack (show e))

  pure result

-- | Build authentication headers for ClickHouse
buildAuthHeaders :: ClickHouseConfig -> [Header]
buildAuthHeaders ClickHouseConfig {..} =
  {- YOUR CODE HERE: Return auth headers if user/password are set -}
  -- Hint: ClickHouse uses X-ClickHouse-User and X-ClickHouse-Key headers
  -- Return [] for no auth, or the headers if credentials exist
  case (chUser, chPassword) of
    (Just user, Just pass) ->
      [ ("X-ClickHouse-User", TE.encodeUtf8 user)
      , ("X-ClickHouse-Key", TE.encodeUtf8 pass)
      ]
    (Just user, Nothing) ->
      [ ("X-ClickHouse-User", TE.encodeUtf8 user)
      ]
    _ -> []

-- | Quote a text value for SQL
quote :: Text -> Text
quote t = "'" <> T.replace "'" "''" t <> "'"

-- | Format Maybe Text for SQL (NULL or quoted string)
formatMaybeText :: Maybe Text -> Text
formatMaybeText Nothing = "NULL"
formatMaybeText (Just t) = quote t

-- | Format UTCTime for ClickHouse DateTime64(3)
-- Format: '2026-03-05 20:46:27.926' (milliseconds precision)
formatTimestamp :: UTCTime -> Text
formatTimestamp t = quote (T.pack (formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S%Q" t))

-- | Calculate approximate percentiles from histogram buckets
-- Returns (p50, p95, p99) in milliseconds
calculatePercentiles :: LatencyBuckets -> (Double, Double, Double)
calculatePercentiles LatencyBuckets {..} =
  let total = lbCount
      -- Find bucket containing each percentile
      p50Bucket = findPercentileBucket 0.50 total
      p95Bucket = findPercentileBucket 0.95 total
      p99Bucket = findPercentileBucket 0.99 total
   in (p50Bucket * 1000.0, p95Bucket * 1000.0, p99Bucket * 1000.0)
  where
    -- Very simple approximation: return the bucket upper bound
    findPercentileBucket :: Double -> Word64 -> Double
    findPercentileBucket p total'
      | total' == 0 = 0.0
      | otherwise =
          let target = floor (p * fromIntegral total') :: Int
              cumulative = zip [lbLe005, lbLe01, lbLe025, lbLe05, lbLe1, lbLe25, lbLe5, lbLe10, lbLe25s, lbLe50s, lbLe100s, lbInf]
                               [0.005,   0.01,   0.025,   0.05,   0.1,   0.25,   0.5,   1.0,    2.5,     5.0,     10.0,     100.0]
           in case dropWhile (\(count, _) -> fromIntegral count < target) cumulative of
                [] -> 100.0  -- Beyond all buckets
                ((_, bound) : _) -> bound
