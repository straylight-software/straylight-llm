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
      MetricsStore (MetricsStore, msRequestsTotal, msRequestsActive, msLatency, msProviders, msStartTime)
    , newMetricsStore

      -- * Recording
    , recordRequest
    , recordRequestComplete
    , recordProviderRequest
    , recordProviderError
    , recordLatency
    , recordProviderSuccess

      -- * Reading
    , getMetrics
    , renderPrometheus
    , getProviderAvgLatency
    , getProviderLatencies

      -- * Types
    , Metrics (Metrics, mRequestsTotal, mRequestsActive, mLatency, mProviders, mStartTime)
    , ProviderMetrics (ProviderMetrics, pmRequestsTotal, pmErrorsAuth, pmErrorsRateLimit, pmErrorsTimeout, pmErrorsUnavailable, pmErrorsOther, pmLatency)
    , LatencyBuckets (LatencyBuckets, lbLe005, lbLe01, lbLe025, lbLe05, lbLe1, lbLe25, lbLe5, lbLe10, lbLe25s, lbLe50s, lbLe100s, lbInf, lbSum, lbCount)
    ) where

import Control.Concurrent.MVar (MVar, newMVar, modifyMVar_, readMVar)
import Data.Aeson (ToJSON (toJSON), FromJSON (parseJSON), object, (.=), withObject, (.:))
import Data.Aeson.Types qualified as AT
import Data.IORef (IORef, newIORef, atomicModifyIORef', readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import Data.Word (Word64)

import Provider.Types (ProviderName (Venice, Vertex, Baseten, OpenRouter, Anthropic), ProviderError (AuthError, RateLimitError, ProviderUnavailable, TimeoutError))


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

instance ToJSON LatencyBuckets where
    toJSON lb = object
        [ "le_005" .= lbLe005 lb
        , "le_01" .= lbLe01 lb
        , "le_025" .= lbLe025 lb
        , "le_05" .= lbLe05 lb
        , "le_1" .= lbLe1 lb
        , "le_25" .= lbLe25 lb
        , "le_5" .= lbLe5 lb
        , "le_10" .= lbLe10 lb
        , "le_25s" .= lbLe25s lb
        , "le_50s" .= lbLe50s lb
        , "le_100s" .= lbLe100s lb
        , "inf" .= lbInf lb
        , "sum" .= lbSum lb
        , "count" .= lbCount lb
        ]

instance FromJSON LatencyBuckets where
    parseJSON = withObject "LatencyBuckets" $ \v -> LatencyBuckets
        <$> v .: "le_005"
        <*> v .: "le_01"
        <*> v .: "le_025"
        <*> v .: "le_05"
        <*> v .: "le_1"
        <*> v .: "le_25"
        <*> v .: "le_5"
        <*> v .: "le_10"
        <*> v .: "le_25s"
        <*> v .: "le_50s"
        <*> v .: "le_100s"
        <*> v .: "inf"
        <*> v .: "sum"
        <*> v .: "count"

instance ToJSON ProviderMetrics where
    toJSON pm = object
        [ "requests_total" .= pmRequestsTotal pm
        , "errors_auth" .= pmErrorsAuth pm
        , "errors_rate_limit" .= pmErrorsRateLimit pm
        , "errors_timeout" .= pmErrorsTimeout pm
        , "errors_unavailable" .= pmErrorsUnavailable pm
        , "errors_other" .= pmErrorsOther pm
        , "latency" .= pmLatency pm
        ]

instance FromJSON ProviderMetrics where
    parseJSON = withObject "ProviderMetrics" $ \v -> ProviderMetrics
        <$> v .: "requests_total"
        <*> v .: "errors_auth"
        <*> v .: "errors_rate_limit"
        <*> v .: "errors_timeout"
        <*> v .: "errors_unavailable"
        <*> v .: "errors_other"
        <*> v .: "latency"

instance ToJSON Metrics where
    toJSON m = object
        [ "requests_total" .= mRequestsTotal m
        , "requests_active" .= mRequestsActive m
        , "latency" .= mLatency m
        , "providers" .= providersToJson (mProviders m)
        , "start_time" .= T.pack (show $ mStartTime m)
        ]
      where
        providersToJson :: Map ProviderName ProviderMetrics -> Map Text ProviderMetrics
        providersToJson = Map.mapKeys providerNameToText
        
        providerNameToText :: ProviderName -> Text
        providerNameToText Venice = "venice"
        providerNameToText Vertex = "vertex"
        providerNameToText Baseten = "baseten"
        providerNameToText OpenRouter = "openrouter"
        providerNameToText Anthropic = "anthropic"

instance FromJSON Metrics where
    parseJSON = withObject "Metrics" $ \v -> do
        requestsTotal <- v .: "requests_total"
        requestsActive <- v .: "requests_active"
        latency <- v .: "latency"
        providersMap <- v .: "providers" :: AT.Parser (Map Text ProviderMetrics)
        startTimeText <- v .: "start_time"
        
        -- Parse providers map with Text keys back to ProviderName keys
        let providers = Map.mapKeys textToProviderName providersMap
        
        -- Parse start time
        startTime <- case reads (T.unpack startTimeText) of
            [(time, "")] -> pure time
            _ -> fail "Invalid start_time"
        
        pure $ Metrics requestsTotal requestsActive latency providers startTime
      where
        textToProviderName :: Text -> ProviderName
        textToProviderName "venice" = Venice
        textToProviderName "vertex" = Vertex
        textToProviderName "baseten" = Baseten
        textToProviderName "openrouter" = OpenRouter
        textToProviderName "anthropic" = Anthropic
        textToProviderName _ = Venice  -- Default fallback


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

-- | Record a successful provider request with latency
recordProviderSuccess :: MetricsStore -> ProviderName -> Double -> IO ()
recordProviderSuccess store provider latencySeconds = do
    recordProviderRequest store provider
    recordLatency store provider latencySeconds


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

-- | Get average latency for a specific provider (in seconds)
-- Returns Nothing if no requests recorded yet
getProviderAvgLatency :: MetricsStore -> ProviderName -> IO (Maybe Double)
getProviderAvgLatency MetricsStore{..} provider = do
    providers <- readMVar msProviders
    pure $ case Map.lookup provider providers of
        Nothing -> Nothing
        Just pm -> 
            let lb = pmLatency pm
                count = lbCount lb
            in if count == 0 
               then Nothing
               else Just (lbSum lb / fromIntegral count)

-- | Get latencies for all providers (sorted by average latency, fastest first)
-- Returns list of (provider, avgLatencySeconds, requestCount)
getProviderLatencies :: MetricsStore -> IO [(ProviderName, Double, Word64)]
getProviderLatencies MetricsStore{..} = do
    providers <- readMVar msProviders
    let latencies = 
          [ (name, lbSum (pmLatency pm) / fromIntegral (lbCount (pmLatency pm)), lbCount (pmLatency pm))
          | (name, pm) <- Map.toList providers
          , lbCount (pmLatency pm) > 0  -- Only include providers with data
          ]
    -- Sort by average latency (ascending = fastest first)
    pure $ sortByLatency latencies
  where
    sortByLatency = foldr insertSorted []
    insertSorted x [] = [x]
    insertSorted x@(_, lat1, _) (y@(_, lat2, _):ys)
        | lat1 <= lat2 = x : y : ys
        | otherwise = y : insertSorted x ys

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
