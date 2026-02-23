-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                    // straylight-llm // resilience/metrics
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The sky above the port was the color of television, tuned to a dead
--      channel."
--
--                                                              — Neuromancer
--
-- Prometheus-style metrics for observability.
-- Thread-safe counters and gauges for request tracking.
--
-- Metrics exposed:
--   - straylight_requests_total (counter)
--   - straylight_requests_active (gauge)
--   - straylight_request_duration_seconds (histogram buckets)
--   - straylight_provider_requests_total (counter, by provider)
--   - straylight_provider_errors_total (counter, by provider, error_type)
--   - straylight_circuit_breaker_state (gauge, by provider)
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Resilience.Metrics
    ( -- * Metrics Store
      MetricsStore (..)
    , newMetricsStore

      -- * Recording
    , recordRequest
    , recordRequestComplete
    , recordProviderRequest
    , recordProviderError
    , recordLatency

      -- * Reading
    , getMetrics
    , renderPrometheus

      -- * Types
    , Metrics (..)
    , ProviderMetrics (..)
    , LatencyBuckets (..)
    ) where

import Control.Concurrent.MVar (MVar, newMVar, modifyMVar_, readMVar)
import Data.IORef (IORef, newIORef, atomicModifyIORef', readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import Data.Word (Word64)

import Provider.Types (ProviderName(..), ProviderError(..))


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Latency histogram buckets (in seconds)
-- Standard Prometheus buckets: 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10
data LatencyBuckets = LatencyBuckets
    { lbLe005 :: !Word64      -- <= 5ms
    , lbLe01 :: !Word64       -- <= 10ms
    , lbLe025 :: !Word64      -- <= 25ms
    , lbLe05 :: !Word64       -- <= 50ms
    , lbLe1 :: !Word64        -- <= 100ms
    , lbLe25 :: !Word64       -- <= 250ms
    , lbLe5 :: !Word64        -- <= 500ms
    , lbLe10 :: !Word64       -- <= 1s
    , lbLe25s :: !Word64      -- <= 2.5s
    , lbLe50s :: !Word64      -- <= 5s
    , lbLe100s :: !Word64     -- <= 10s
    , lbInf :: !Word64        -- > 10s (always == total)
    , lbSum :: !Double        -- Sum of all observations
    , lbCount :: !Word64      -- Total count
    }
    deriving (Eq, Show)

-- | Empty latency buckets
emptyBuckets :: LatencyBuckets
emptyBuckets = LatencyBuckets 0 0 0 0 0 0 0 0 0 0 0 0 0.0 0

-- | Record a latency observation into buckets
recordBucket :: Double -> LatencyBuckets -> LatencyBuckets
recordBucket latency LatencyBuckets{..} = LatencyBuckets
    { lbLe005 = if latency <= 0.005 then lbLe005 + 1 else lbLe005
    , lbLe01 = if latency <= 0.01 then lbLe01 + 1 else lbLe01
    , lbLe025 = if latency <= 0.025 then lbLe025 + 1 else lbLe025
    , lbLe05 = if latency <= 0.05 then lbLe05 + 1 else lbLe05
    , lbLe1 = if latency <= 0.1 then lbLe1 + 1 else lbLe1
    , lbLe25 = if latency <= 0.25 then lbLe25 + 1 else lbLe25
    , lbLe5 = if latency <= 0.5 then lbLe5 + 1 else lbLe5
    , lbLe10 = if latency <= 1.0 then lbLe10 + 1 else lbLe10
    , lbLe25s = if latency <= 2.5 then lbLe25s + 1 else lbLe25s
    , lbLe50s = if latency <= 5.0 then lbLe50s + 1 else lbLe50s
    , lbLe100s = if latency <= 10.0 then lbLe100s + 1 else lbLe100s
    , lbInf = lbInf + 1  -- Always increment (cumulative)
    , lbSum = lbSum + latency
    , lbCount = lbCount + 1
    }

-- | Per-provider metrics
data ProviderMetrics = ProviderMetrics
    { pmRequestsTotal :: !Word64
    , pmErrorsAuth :: !Word64
    , pmErrorsRateLimit :: !Word64
    , pmErrorsTimeout :: !Word64
    , pmErrorsUnavailable :: !Word64
    , pmErrorsOther :: !Word64
    , pmLatency :: !LatencyBuckets
    }
    deriving (Eq, Show)

-- | Empty provider metrics
emptyProviderMetrics :: ProviderMetrics
emptyProviderMetrics = ProviderMetrics 0 0 0 0 0 0 emptyBuckets

-- | Aggregated metrics snapshot
data Metrics = Metrics
    { mRequestsTotal :: !Word64           -- Total requests received
    , mRequestsActive :: !Int             -- Currently in-flight
    , mLatency :: !LatencyBuckets         -- Overall latency histogram
    , mProviders :: !(Map ProviderName ProviderMetrics)
    , mStartTime :: !UTCTime              -- Server start time
    }
    deriving (Eq, Show)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // store
-- ════════════════════════════════════════════════════════════════════════════

-- | Thread-safe metrics store
data MetricsStore = MetricsStore
    { msRequestsTotal :: !(IORef Word64)
    , msRequestsActive :: !(IORef Int)
    , msLatency :: !(MVar LatencyBuckets)
    , msProviders :: !(MVar (Map ProviderName ProviderMetrics))
    , msStartTime :: !UTCTime
    }

-- | Create a new metrics store
newMetricsStore :: IO MetricsStore
newMetricsStore = do
    requestsTotal <- newIORef 0
    requestsActive <- newIORef 0
    latency <- newMVar emptyBuckets
    providers <- newMVar Map.empty
    startTime <- getCurrentTime
    pure MetricsStore
        { msRequestsTotal = requestsTotal
        , msRequestsActive = requestsActive
        , msLatency = latency
        , msProviders = providers
        , msStartTime = startTime
        }


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // recording
-- ════════════════════════════════════════════════════════════════════════════

-- | Record a new request starting
-- Returns the start time for latency calculation
recordRequest :: MetricsStore -> IO UTCTime
recordRequest MetricsStore{..} = do
    atomicModifyIORef' msRequestsTotal (\n -> (n + 1, ()))
    atomicModifyIORef' msRequestsActive (\n -> (n + 1, ()))
    getCurrentTime

-- | Record a request completing
recordRequestComplete :: MetricsStore -> UTCTime -> IO ()
recordRequestComplete MetricsStore{..} startTime = do
    atomicModifyIORef' msRequestsActive (\n -> (n - 1, ()))
    endTime <- getCurrentTime
    let latencySeconds = realToFrac (diffUTCTime endTime startTime) :: Double
    modifyMVar_ msLatency (pure . recordBucket latencySeconds)

-- | Record a provider request
recordProviderRequest :: MetricsStore -> ProviderName -> IO ()
recordProviderRequest MetricsStore{..} provider = 
    modifyMVar_ msProviders $ \m -> do
        let pm = Map.findWithDefault emptyProviderMetrics provider m
        pure $ Map.insert provider (pm { pmRequestsTotal = pmRequestsTotal pm + 1 }) m

-- | Record a provider error
recordProviderError :: MetricsStore -> ProviderName -> ProviderError -> IO ()
recordProviderError MetricsStore{..} provider err =
    modifyMVar_ msProviders $ \m -> do
        let pm = Map.findWithDefault emptyProviderMetrics provider m
        let pm' = case err of
                AuthError _ -> pm { pmErrorsAuth = pmErrorsAuth pm + 1 }
                RateLimitError _ -> pm { pmErrorsRateLimit = pmErrorsRateLimit pm + 1 }
                TimeoutError _ -> pm { pmErrorsTimeout = pmErrorsTimeout pm + 1 }
                ProviderUnavailable _ -> pm { pmErrorsUnavailable = pmErrorsUnavailable pm + 1 }
                _ -> pm { pmErrorsOther = pmErrorsOther pm + 1 }
        pure $ Map.insert provider pm' m

-- | Record provider latency
recordLatency :: MetricsStore -> ProviderName -> Double -> IO ()
recordLatency MetricsStore{..} provider latencySeconds =
    modifyMVar_ msProviders $ \m -> do
        let pm = Map.findWithDefault emptyProviderMetrics provider m
        let pm' = pm { pmLatency = recordBucket latencySeconds (pmLatency pm) }
        pure $ Map.insert provider pm' m


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // reading
-- ════════════════════════════════════════════════════════════════════════════

-- | Get current metrics snapshot
getMetrics :: MetricsStore -> IO Metrics
getMetrics MetricsStore{..} = do
    requestsTotal <- readIORef msRequestsTotal
    requestsActive <- readIORef msRequestsActive
    latency <- readMVar msLatency
    providers <- readMVar msProviders
    pure Metrics
        { mRequestsTotal = requestsTotal
        , mRequestsActive = requestsActive
        , mLatency = latency
        , mProviders = providers
        , mStartTime = msStartTime
        }

-- | Render metrics in Prometheus text format
renderPrometheus :: Metrics -> Text
renderPrometheus Metrics{..} = T.unlines $
    -- Help and type declarations
    [ "# HELP straylight_requests_total Total number of requests received"
    , "# TYPE straylight_requests_total counter"
    , "straylight_requests_total " <> showT mRequestsTotal

    , "# HELP straylight_requests_active Number of requests currently in flight"
    , "# TYPE straylight_requests_active gauge"
    , "straylight_requests_active " <> showT mRequestsActive

    -- Overall latency histogram
    , "# HELP straylight_request_duration_seconds Request latency histogram"
    , "# TYPE straylight_request_duration_seconds histogram"
    ] <> renderLatencyBuckets "straylight_request_duration_seconds" "" mLatency
    
    -- Per-provider metrics
    <> concatMap renderProvider (Map.toList mProviders)
  where
    showT :: Show a => a -> Text
    showT = T.pack . show

    renderLatencyBuckets :: Text -> Text -> LatencyBuckets -> [Text]
    renderLatencyBuckets name labels LatencyBuckets{..} =
        [ name <> "_bucket{le=\"0.005\"" <> labels <> "} " <> showT lbLe005
        , name <> "_bucket{le=\"0.01\"" <> labels <> "} " <> showT lbLe01
        , name <> "_bucket{le=\"0.025\"" <> labels <> "} " <> showT lbLe025
        , name <> "_bucket{le=\"0.05\"" <> labels <> "} " <> showT lbLe05
        , name <> "_bucket{le=\"0.1\"" <> labels <> "} " <> showT lbLe1
        , name <> "_bucket{le=\"0.25\"" <> labels <> "} " <> showT lbLe25
        , name <> "_bucket{le=\"0.5\"" <> labels <> "} " <> showT lbLe5
        , name <> "_bucket{le=\"1\"" <> labels <> "} " <> showT lbLe10
        , name <> "_bucket{le=\"2.5\"" <> labels <> "} " <> showT lbLe25s
        , name <> "_bucket{le=\"5\"" <> labels <> "} " <> showT lbLe50s
        , name <> "_bucket{le=\"10\"" <> labels <> "} " <> showT lbLe100s
        , name <> "_bucket{le=\"+Inf\"" <> labels <> "} " <> showT lbInf
        , name <> "_sum" <> (if T.null labels then "" else "{" <> T.drop 1 labels <> "}") <> " " <> T.pack (show lbSum)
        , name <> "_count" <> (if T.null labels then "" else "{" <> T.drop 1 labels <> "}") <> " " <> showT lbCount
        ]

    renderProvider :: (ProviderName, ProviderMetrics) -> [Text]
    renderProvider (name, ProviderMetrics{..}) =
        let p = T.toLower (T.pack (show name))
            labels = ",provider=\"" <> p <> "\""
        in
        [ "# HELP straylight_provider_requests_total Total requests to provider"
        , "# TYPE straylight_provider_requests_total counter"
        , "straylight_provider_requests_total{provider=\"" <> p <> "\"} " <> showT pmRequestsTotal

        , "# HELP straylight_provider_errors_total Total errors by type"
        , "# TYPE straylight_provider_errors_total counter"
        , "straylight_provider_errors_total{provider=\"" <> p <> "\",error_type=\"auth\"} " <> showT pmErrorsAuth
        , "straylight_provider_errors_total{provider=\"" <> p <> "\",error_type=\"rate_limit\"} " <> showT pmErrorsRateLimit
        , "straylight_provider_errors_total{provider=\"" <> p <> "\",error_type=\"timeout\"} " <> showT pmErrorsTimeout
        , "straylight_provider_errors_total{provider=\"" <> p <> "\",error_type=\"unavailable\"} " <> showT pmErrorsUnavailable
        , "straylight_provider_errors_total{provider=\"" <> p <> "\",error_type=\"other\"} " <> showT pmErrorsOther

        -- Provider latency histogram
        , "# HELP straylight_provider_request_duration_seconds Provider latency histogram"
        , "# TYPE straylight_provider_request_duration_seconds histogram"
        ] <> renderLatencyBuckets "straylight_provider_request_duration_seconds" labels pmLatency
