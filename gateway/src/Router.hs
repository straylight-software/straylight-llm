-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                              // straylight-llm // router
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd made the classic mistake, the one he'd sworn he'd never make.
--      He'd fallen for it. He'd fallen for the world."
--
--                                                              — Neuromancer
--
-- Fallback chain router for LLM provider selection.
-- Priority: Venice -> Vertex -> Baseten -> OpenRouter
--
-- On failure, routes to next provider if error is retryable.
-- Non-retryable errors (auth, invalid request) fail immediately.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Router
    ( -- * Router
      Router (Router, routerManager, routerProviders, routerConfig, routerVeniceConfig, routerVertexConfig, routerBasetenConfig, routerOpenRouterConfig, routerAnthropicConfig, routerProofCache, routerModelRegistry, routerMetrics, routerBackpressure, routerCircuitBreakers, routerRequestHistory, routerAdminSemaphore, routerResponseCache, routerEventBroadcaster)
    , makeRouter

      -- * Routing
    , routeChat
    , routeChatStream
    , routeEmbeddings
    , routeModels

      -- * Proof Access
    , lookupProof
    , listRecentProofs

      -- * Provider Chain
    , ProviderChain
    , defaultChain
    
      -- * Observability (for API endpoints)
    , RequestHistory (RequestHistory, rhRequestId, rhModel, rhProvider, rhSuccess, rhLatencyMs, rhTimestamp)
    , getRouterMetrics
    , getProviderCircuitStats
    , lookupRequestHistory
    
      -- * SSE Events (re-export)
    , EventBroadcaster
    , subscribe
    , encodeSSEEvent
    ) where

import Data.Aeson (ToJSON (toJSON), FromJSON (parseJSON), encode, object, (.=), withObject, (.:))
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, newIORef, readIORef, atomicModifyIORef')
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)

import Network.HTTP.Client qualified as HC
import Network.HTTP.Client.TLS qualified as HCT

import Coeffect.Discharge (fromGatewayTracking)
import Coeffect.Types (DischargeProof)
import Config
import Effects.Graded (GatewayM, runGatewayM, recordRequestId, recordProvider, withRetry, liftGatewayIO)
import Provider.Types
import Provider.Venice (makeVeniceProvider)
import Provider.Vertex (makeVertexProvider)
import Provider.Baseten (makeBasetenProvider)
import Provider.OpenRouter (makeOpenRouterProvider)
import Provider.Anthropic (makeAnthropicProvider)
import Provider.ModelRegistry (ModelRegistry, makeModelRegistry, registrySupportsModel)
import Resilience.Backpressure (RequestSemaphore, newRequestSemaphore, tryWithRequestSlot)
import Resilience.Cache (BoundedCache, CacheConfig (ccMaxSize, ccTTL), defaultCacheConfig, newBoundedCache, cacheInsert, cacheLookup)
import Resilience.CircuitBreaker 
    ( CircuitBreaker
    , CircuitStats (csFailureCount, csLastFailure)
    , CircuitBreakerConfig (cbcFailureThreshold)
    , defaultCircuitBreakerConfig
    , newCircuitBreaker
    , withCircuitBreaker
    , getCircuitStats
    , getCircuitState
    )
import Resilience.CircuitBreaker qualified as CB
import Resilience.Metrics (MetricsStore, Metrics, newMetricsStore, recordRequest, recordRequestComplete, recordProviderRequest, recordProviderError, getMetrics, getProviderLatencies, recordProviderSuccess)
import Streaming.Events
    ( EventBroadcaster
    , CircuitState (..)
    , newEventBroadcaster
    , subscribe
    , encodeSSEEvent
    , emitRequestStarted
    , emitRequestCompleted
    , emitProofGenerated
    , emitProviderStatus
    )
import Types

import Coeffect.Types (dpCoeffects, dpSignature, coeffectToText)
import Effects.Graded (gpProvidersUsed)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Provider chain (ordered list of providers to try)
type ProviderChain = [Provider]

-- | Proof cache (maps request ID to discharge proof)
-- Limited to most recent N proofs to prevent unbounded growth
type ProofCache = Map Text DischargeProof

-- | Maximum number of proofs to cache
maxProofCache :: Int
maxProofCache = 1000

-- | Request history entry for audit trail
data RequestHistory = RequestHistory
    { rhRequestId :: !Text
    , rhModel :: !Text
    , rhProvider :: !(Maybe ProviderName)
    , rhSuccess :: !Bool
    , rhLatencyMs :: !Double
    , rhTimestamp :: !Text  -- ISO 8601 timestamp
    }
    deriving (Eq, Show)

instance ToJSON RequestHistory where
    toJSON rh = object
        [ "request_id" .= rhRequestId rh
        , "model" .= rhModel rh
        , "provider" .= rhProvider rh
        , "success" .= rhSuccess rh
        , "latency_ms" .= rhLatencyMs rh
        , "timestamp" .= rhTimestamp rh
        ]

instance FromJSON RequestHistory where
    parseJSON = withObject "RequestHistory" $ \v -> RequestHistory
        <$> v .: "request_id"
        <*> v .: "model"
        <*> v .: "provider"
        <*> v .: "success"
        <*> v .: "latency_ms"
        <*> v .: "timestamp"

-- | Router state with full resilience infrastructure
data Router = Router
    { routerManager :: HC.Manager
    , routerProviders :: ProviderChain
    , routerConfig :: Config
    , routerVeniceConfig :: IORef ProviderConfig
    , routerVertexConfig :: IORef ProviderConfig
    , routerBasetenConfig :: IORef ProviderConfig
    , routerOpenRouterConfig :: IORef ProviderConfig
    , routerAnthropicConfig :: IORef ProviderConfig  -- Direct Anthropic API (last in chain)
    , routerProofCache :: IORef ProofCache
    , routerModelRegistry :: ModelRegistry  -- Dynamic model registry with sync
    
    -- Resilience infrastructure (billion-agent scale)
    , routerMetrics :: MetricsStore                  -- Prometheus-style metrics
    , routerBackpressure :: RequestSemaphore         -- Limit concurrent requests
    , routerCircuitBreakers :: Map ProviderName CircuitBreaker  -- One per provider
    , routerRequestHistory :: BoundedCache Text RequestHistory   -- Audit trail
    , routerAdminSemaphore :: RequestSemaphore       -- Rate limit admin endpoints
    
    -- Response cache (for identical queries - billion-agent optimization)
    , routerResponseCache :: BoundedCache LBS.ByteString ChatResponse  -- Hash of request -> response
    
    -- Real-time event broadcasting (SSE)
    , routerEventBroadcaster :: EventBroadcaster     -- SSE event broadcaster
    }

-- | Default provider chain order
-- Anthropic is last: direct API access, used when explicitly requested or all others fail
defaultChain :: [ProviderName]
defaultChain = [Venice, Vertex, Baseten, OpenRouter, Anthropic]


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // construction
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a router from config
makeRouter :: Config -> IO Router
makeRouter config = do
    -- Create HTTP manager optimized for high-throughput billion-agent scale
    -- Key optimizations:
    --   1. Increased connection pool (10 -> 100 per host)
    --   2. Longer idle timeout (30s -> 60s) to reuse connections
    --   3. Response timeout from config
    let settings = HCT.tlsManagerSettings
            { HC.managerResponseTimeout =
                HC.responseTimeoutMicro (cfgRequestTimeout config * 1000000)
            -- Connection pool size per host (default is 10, we use 100 for swarm scale)
            , HC.managerConnCount = 100
            -- Idle connection timeout in microseconds (60 seconds)
            , HC.managerIdleConnectionCount = 200
            }
    manager <- HC.newManager settings

    -- Create config refs (allows runtime updates)
    veniceRef <- newIORef (cfgVenice config)
    vertexRef <- newIORef (cfgVertex config)
    basetenRef <- newIORef (cfgBaseten config)
    openrouterRef <- newIORef (cfgOpenRouter config)
    anthropicRef <- newIORef (cfgAnthropic config)

    -- Create providers
    let veniceProvider = makeVeniceProvider veniceRef
    vertexProvider <- makeVertexProvider vertexRef
    let basetenProvider = makeBasetenProvider basetenRef
    let openrouterProvider = makeOpenRouterProvider openrouterRef
    let anthropicProvider = makeAnthropicProvider anthropicRef

    -- Build chain in priority order (Anthropic last for direct API access)
    let providers = [veniceProvider, vertexProvider, basetenProvider, openrouterProvider, anthropicProvider]

    -- Create proof cache
    proofCacheRef <- newIORef Map.empty

    -- Create model registry with 5-minute sync interval
    modelRegistry <- makeModelRegistry manager providers 300

    -- Initialize resilience infrastructure for billion-agent scale
    metricsStore <- newMetricsStore
    
    -- Backpressure: limit to 10000 concurrent requests (prevent OOM)
    backpressure <- newRequestSemaphore 10000
    
    -- Circuit breakers: one per provider
    veniceCB <- newCircuitBreaker "venice" defaultCircuitBreakerConfig
    vertexCB <- newCircuitBreaker "vertex" defaultCircuitBreakerConfig
    basetenCB <- newCircuitBreaker "baseten" defaultCircuitBreakerConfig
    openrouterCB <- newCircuitBreaker "openrouter" defaultCircuitBreakerConfig
    anthropicCB <- newCircuitBreaker "anthropic" defaultCircuitBreakerConfig
    
    let circuitBreakers = Map.fromList
            [ (Venice, veniceCB)
            , (Vertex, vertexCB)
            , (Baseten, basetenCB)
            , (OpenRouter, openrouterCB)
            , (Anthropic, anthropicCB)
            ]
    
    -- Request history cache (5000 most recent requests for audit)
    requestHistory <- newBoundedCache defaultCacheConfig { ccMaxSize = 5000 }
    
    -- Admin endpoint rate limiting (10 concurrent requests max)
    adminSemaphore <- newRequestSemaphore 10
    
    -- Response cache for identical queries (billion-agent optimization)
    -- Cache up to 10000 unique request hashes with 5-minute TTL
    responseCache <- newBoundedCache defaultCacheConfig 
        { ccMaxSize = 10000
        , ccTTL = Just 300  -- 5 minutes
        }
    
    -- Event broadcaster for SSE real-time updates
    eventBroadcaster <- newEventBroadcaster

    pure Router
        { routerManager = manager
        , routerProviders = providers
        , routerConfig = config
        , routerVeniceConfig = veniceRef
        , routerVertexConfig = vertexRef
        , routerBasetenConfig = basetenRef
        , routerOpenRouterConfig = openrouterRef
        , routerAnthropicConfig = anthropicRef
        , routerProofCache = proofCacheRef
        , routerModelRegistry = modelRegistry
        , routerMetrics = metricsStore
        , routerBackpressure = backpressure
        , routerCircuitBreakers = circuitBreakers
        , routerRequestHistory = requestHistory
        , routerAdminSemaphore = adminSemaphore
        , routerResponseCache = responseCache
        , routerEventBroadcaster = eventBroadcaster
        }


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // routing
-- ════════════════════════════════════════════════════════════════════════════

-- | Route a chat completion request through the provider chain
-- Now with full resilience: backpressure, circuit breakers, metrics, history, response caching
routeChat :: Router -> Text -> ChatRequest -> IO (Either ProviderError ChatResponse)
routeChat router requestId req = do
    -- Record request start for metrics
    startTime <- recordRequest (routerMetrics router)
    let modelId = unModelId $ crModel req
    
    -- Emit request.started event
    let startTimestamp = T.pack $ show startTime
    emitRequestStarted (routerEventBroadcaster router) requestId modelId startTimestamp
    
    -- Check response cache first (billion-agent optimization)
    -- Only cache deterministic requests (temperature=0 or seed set)
    let cacheKey = encode req  -- JSON encoding as cache key
        isCacheable = crTemperature req == Just (Temperature 0) || crSeed req /= Nothing
    
    cachedResponse <- if isCacheable
        then cacheLookup (routerResponseCache router) cacheKey
        else pure Nothing
    
    case cachedResponse of
        Just resp -> do
            -- Cache hit! Return immediately
            recordRequestComplete (routerMetrics router) startTime
            endTime <- getCurrentTime
            let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double
                endTimestamp = T.pack $ show endTime
            emitRequestCompleted (routerEventBroadcaster router) requestId modelId (Just "cache") True latencyMs Nothing endTimestamp
            pure $ Right resp
        
        Nothing -> do
            -- Cache miss, proceed with provider call
            -- Apply backpressure (fail fast if overloaded)
            mResult <- tryWithRequestSlot (routerBackpressure router) $ do
                -- Partition providers by model support (uses registry)
                modelSupportProviders <- partitionByModelSupport (routerModelRegistry router) modelId (routerProviders router)
                -- Sort by historical latency (fastest first) for billion-agent optimization
                orderedProviders <- sortProvidersByLatency (routerMetrics router) modelSupportProviders
                
                -- Run the computation and capture tracking
                (result, _grade, prov, coeff) <- runGatewayM $ do
                    recordRequestId requestId
                    let ctx = RequestContext
                            { rcManager = routerManager router
                            , rcRequestId = requestId
                            , rcClientIp = Nothing
                            }

                    -- Find enabled providers from the pre-ordered list
                    enabledProviders <- filterEnabledProviders orderedProviders

                    -- Try each provider with circuit breakers
                    tryProvidersWithCircuitBreakers router enabledProviders $ \provider ->
                        providerChat provider ctx req
                
                -- Cache successful responses for cacheable requests
                case result of
                    Right resp | isCacheable -> 
                        cacheInsert (routerResponseCache router) cacheKey resp
                    _ -> pure ()
                
                -- Generate discharge proof
                let reqBody = LBS.toStrict $ encode req
                    respBody = either (const "") (LBS.toStrict . encode) result
                proof <- fromGatewayTracking prov coeff reqBody respBody
                
                -- Store proof in cache
                storeProof router requestId proof
                
                -- Emit proof.generated event
                emitProofGeneratedFromProof (routerEventBroadcaster router) requestId proof
                
                pure (result, prov)
            
            -- Record completion
            recordRequestComplete (routerMetrics router) startTime
            
            -- Handle backpressure rejection
            case mResult of
                Nothing -> do
                    -- Emit request.completed with error
                    endTime <- getCurrentTime
                    let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double
                        endTimestamp = T.pack $ show endTime
                    emitRequestCompleted (routerEventBroadcaster router) requestId modelId Nothing False latencyMs (Just "Gateway overloaded (503)") endTimestamp
                    pure $ Left $ ProviderUnavailable "Gateway overloaded (503)"
                Just (result, prov) -> do
                    -- Emit request.completed event
                    endTime <- getCurrentTime
                    let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double
                        success = either (const False) (const True) result
                        errMsg = either (Just . providerErrorToText) (const Nothing) result
                        provider = safeHead (gpProvidersUsed prov)
                        endTimestamp = T.pack $ show endTime
                    
                    -- Store in request history for audit (with provider)
                    storeRequestHistory router requestId modelId provider result startTime
                    
                    emitRequestCompleted (routerEventBroadcaster router) requestId modelId provider success latencyMs errMsg endTimestamp
                    
                    pure result

-- | Route a streaming chat completion through the provider chain
routeChatStream :: Router -> Text -> ChatRequest -> StreamCallback -> IO (Either ProviderError ())
routeChatStream router requestId req callback = do
    startTime <- recordRequest (routerMetrics router)
    let modelId = unModelId $ crModel req
    
    -- Emit request.started event
    let startTimestamp = T.pack $ show startTime
    emitRequestStarted (routerEventBroadcaster router) requestId modelId startTimestamp
    
    mResult <- tryWithRequestSlot (routerBackpressure router) $ do
        modelSupportProviders <- partitionByModelSupport (routerModelRegistry router) modelId (routerProviders router)
        -- Sort by historical latency (fastest first) for billion-agent optimization
        orderedProviders <- sortProvidersByLatency (routerMetrics router) modelSupportProviders
        
        (result, _grade, prov, coeff) <- runGatewayM $ do
            recordRequestId requestId
            let ctx = RequestContext
                    { rcManager = routerManager router
                    , rcRequestId = requestId
                    , rcClientIp = Nothing
                    }

            enabledProviders <- filterEnabledProviders orderedProviders

            tryProvidersWithCircuitBreakers router enabledProviders $ \provider ->
                providerChatStream provider ctx req callback
        
        -- Generate discharge proof (streaming has no response body to hash)
        let reqBody = LBS.toStrict $ encode req
        proof <- fromGatewayTracking prov coeff reqBody ""
        
        storeProof router requestId proof
        
        -- Emit proof.generated event
        emitProofGeneratedFromProof (routerEventBroadcaster router) requestId proof
        
        pure (result, prov)
    
    recordRequestComplete (routerMetrics router) startTime
    
    case mResult of
        Nothing -> do
            endTime <- getCurrentTime
            let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double
                endTimestamp = T.pack $ show endTime
            emitRequestCompleted (routerEventBroadcaster router) requestId modelId Nothing False latencyMs (Just "Gateway overloaded (503)") endTimestamp
            pure $ Left $ ProviderUnavailable "Gateway overloaded (503)"
        Just (result, prov) -> do
            -- Emit request.completed event
            endTime <- getCurrentTime
            let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double
                success = either (const False) (const True) result
                errMsg = either (Just . providerErrorToText) (const Nothing) result
                provider = safeHead (gpProvidersUsed prov)
                endTimestamp = T.pack $ show endTime
            
            -- Store in request history for audit (with provider)
            storeRequestHistory router requestId modelId provider result startTime
            
            emitRequestCompleted (routerEventBroadcaster router) requestId modelId provider success latencyMs errMsg endTimestamp
            
            pure result

-- | Route an embeddings request through the provider chain
routeEmbeddings :: Router -> Text -> EmbeddingRequest -> IO (Either ProviderError EmbeddingResponse)
routeEmbeddings router requestId req = do
    startTime <- recordRequest (routerMetrics router)
    let modelId = unModelId $ embModel req
    
    -- Emit request.started event
    let startTimestamp = T.pack $ show startTime
    emitRequestStarted (routerEventBroadcaster router) requestId modelId startTimestamp
    
    mResult <- tryWithRequestSlot (routerBackpressure router) $ do
        (result, _grade, prov, coeff) <- runGatewayM $ do
            recordRequestId requestId
            let ctx = RequestContext
                    { rcManager = routerManager router
                    , rcRequestId = requestId
                    , rcClientIp = Nothing
                    }

            enabledProviders <- filterEnabledProviders (routerProviders router)

            tryProvidersWithCircuitBreakers router enabledProviders $ \provider ->
                providerEmbeddings provider ctx req
        
        -- Generate discharge proof
        let reqBody = LBS.toStrict $ encode req
            respBody = either (const "") (LBS.toStrict . encode) result
        proof <- fromGatewayTracking prov coeff reqBody respBody
        
        storeProof router requestId proof
        
        -- Emit proof.generated event
        emitProofGeneratedFromProof (routerEventBroadcaster router) requestId proof
        
        pure (result, prov)
    
    recordRequestComplete (routerMetrics router) startTime
    
    case mResult of
        Nothing -> do
            endTime <- getCurrentTime
            let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double
                endTimestamp = T.pack $ show endTime
            emitRequestCompleted (routerEventBroadcaster router) requestId modelId Nothing False latencyMs (Just "Gateway overloaded (503)") endTimestamp
            pure $ Left $ ProviderUnavailable "Gateway overloaded (503)"
        Just (result, prov) -> do
            -- Emit request.completed event
            endTime <- getCurrentTime
            let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double
                success = either (const False) (const True) result
                errMsg = either (Just . providerErrorToText) (const Nothing) result
                provider = safeHead (gpProvidersUsed prov)
                endTimestamp = T.pack $ show endTime
            
            -- Store in request history for audit (with provider)
            storeRequestHistory router requestId modelId provider result startTime
            
            emitRequestCompleted (routerEventBroadcaster router) requestId modelId provider success latencyMs errMsg endTimestamp
            
            pure result

-- | Get models from all enabled providers
routeModels :: Router -> Text -> IO (Either ProviderError ModelList)
routeModels router requestId = do
    startTime <- recordRequest (routerMetrics router)
    let modelType = "models-list" :: Text
    
    -- Emit request.started event
    let startTimestamp = T.pack $ show startTime
    emitRequestStarted (routerEventBroadcaster router) requestId modelType startTimestamp
    
    mResult <- tryWithRequestSlot (routerBackpressure router) $ do
        (result, _grade, prov, coeff) <- runGatewayM $ do
            recordRequestId requestId
            let ctx = RequestContext
                    { rcManager = routerManager router
                    , rcRequestId = requestId
                    , rcClientIp = Nothing
                    }

            enabledProviders <- filterEnabledProviders (routerProviders router)

            -- Collect models from all providers (no circuit breaker for this read-only op)
            results <- mapM (\p -> providerModels p ctx) enabledProviders

            -- Merge successful model lists
            let successModels = concatMap extractModels results

            if null successModels
                then pure $ Left $ ProviderUnavailable "No providers available"
                else pure $ Right $ ModelList "list" successModels
        
        -- Generate discharge proof (models endpoint has no request body)
        let respBody = either (const "") (LBS.toStrict . encode) result
        proof <- fromGatewayTracking prov coeff "" respBody
        
        storeProof router requestId proof
        
        -- Emit proof.generated event
        emitProofGeneratedFromProof (routerEventBroadcaster router) requestId proof
        
        pure (result, prov)
    
    recordRequestComplete (routerMetrics router) startTime
    
    case mResult of
        Nothing -> do
            endTime <- getCurrentTime
            let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double
                endTimestamp = T.pack $ show endTime
            emitRequestCompleted (routerEventBroadcaster router) requestId modelType Nothing False latencyMs (Just "Gateway overloaded (503)") endTimestamp
            pure $ Left $ ProviderUnavailable "Gateway overloaded (503)"
        Just (result, prov) -> do
            -- Emit request.completed event
            endTime <- getCurrentTime
            let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double
                success = either (const False) (const True) result
                errMsg = either (Just . providerErrorToText) (const Nothing) result
                provider = safeHead (gpProvidersUsed prov)
                endTimestamp = T.pack $ show endTime
            
            -- Store in request history for audit (with provider)
            storeRequestHistory router requestId modelType provider result startTime
            
            emitRequestCompleted (routerEventBroadcaster router) requestId modelType provider success latencyMs errMsg endTimestamp
            
            pure result
  where
    extractModels (Success (ModelList _ models)) = models
    extractModels _ = []


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Filter to only enabled providers
filterEnabledProviders :: [Provider] -> GatewayM [Provider]
filterEnabledProviders providers = do
    enabled <- mapM (\p -> (,) p <$> providerEnabled p) providers
    pure [p | (p, True) <- enabled]

-- | Partition providers by whether they support a given model
-- Uses the model registry for dynamic model support (fetched from provider APIs)
-- Returns providers ordered: supporting first, then others
partitionByModelSupport :: ModelRegistry -> Text -> [Provider] -> IO [Provider]
partitionByModelSupport registry modelId providers = do
    -- Check each provider against the registry
    supported <- mapM checkSupport providers
    let (supporting, others) = foldr classify ([], []) (zip providers supported)
    pure $ supporting ++ others
  where
    checkSupport p = registrySupportsModel registry (providerName p) modelId
    classify (p, True) (s, o) = (p : s, o)
    classify (p, False) (s, o) = (s, p : o)

-- | Sort providers by historical latency (fastest first)
-- Providers with no latency data are put at the end (preserves original order among them)
-- This is used AFTER partitionByModelSupport to optimize within model-supporting providers
sortProvidersByLatency :: MetricsStore -> [Provider] -> IO [Provider]
sortProvidersByLatency metrics providers = do
    latencies <- getProviderLatencies metrics
    let latencyMap = Map.fromList [(name, lat) | (name, lat, _) <- latencies]
    -- Stable sort: providers with latency data sorted by latency,
    -- providers without data keep original order at end
    let (withData, withoutData) = foldr partitionByData ([], []) providers
          where
            partitionByData p (wd, wod) =
                case Map.lookup (providerName p) latencyMap of
                    Just _ -> (p : wd, wod)
                    Nothing -> (wd, p : wod)
        -- Sort those with data by latency
        sortedWithData = sortByLatency latencyMap withData
    pure $ sortedWithData ++ withoutData
  where
    sortByLatency latencyMap = foldr (insertByLatency latencyMap) []
    insertByLatency _ p [] = [p]
    insertByLatency lm p (q:qs) =
        let pLat = Map.findWithDefault maxLatency (providerName p) lm
            qLat = Map.findWithDefault maxLatency (providerName q) lm
        in if pLat <= qLat then p : q : qs else q : insertByLatency lm p qs
    maxLatency = 1000.0 :: Double  -- 1000 seconds = effectively infinite

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // proof management
-- ════════════════════════════════════════════════════════════════════════════

-- | Store a proof in the cache, evicting oldest if over capacity
storeProof :: Router -> Text -> DischargeProof -> IO ()
storeProof router requestId proof = 
    atomicModifyIORef' (routerProofCache router) $ \cache ->
        let cache' = Map.insert requestId proof cache
            -- Evict oldest entries if over capacity
            trimmed = if Map.size cache' > maxProofCache
                      then Map.fromList $ drop (Map.size cache' - maxProofCache) $ Map.toList cache'
                      else cache'
        in (trimmed, ())

-- | Look up a proof by request ID
lookupProof :: Router -> Text -> IO (Maybe DischargeProof)
lookupProof router requestId = do
    cache <- readIORef (routerProofCache router)
    pure $ Map.lookup requestId cache

-- | List recent proofs (most recent N)
listRecentProofs :: Router -> Int -> IO [DischargeProof]
listRecentProofs router n = do
    cache <- readIORef (routerProofCache router)
    pure $ take n $ reverse $ Map.elems cache


-- ════════════════════════════════════════════════════════════════════════════
--                                                  // resilience integration
-- ════════════════════════════════════════════════════════════════════════════

-- | Try providers with circuit breakers (fail fast if circuit open)
-- Also emits SSE events when circuit breaker state changes.
-- Records latency metrics on success for latency-based provider selection.
tryProvidersWithCircuitBreakers :: Router -> [Provider] -> (Provider -> GatewayM (ProviderResult a)) -> GatewayM (Either ProviderError a)
tryProvidersWithCircuitBreakers router providers action = go providers Nothing
  where
    go [] lastErr = pure $ Left $ maybe (ProviderUnavailable "All providers failed") id lastErr
    go (p:ps) _lastErr = do
        let pName = providerName p
        
        -- Record provider request in metrics
        liftGatewayIO $ recordProviderRequest (routerMetrics router) pName
        
        -- Get circuit breaker for this provider
        case Map.lookup pName (routerCircuitBreakers router) of
            Nothing -> do
                -- No circuit breaker (shouldn't happen, but handle gracefully)
                result <- action p
                handleResult result ps
            
            Just cb -> do
                -- Capture circuit state BEFORE the operation
                stateBefore <- liftGatewayIO $ getCircuitState cb
                
                -- Time the provider call for latency tracking
                callStart <- liftGatewayIO getCurrentTime
                
                -- Check circuit breaker - need to convert ProviderResult to Either for circuit breaker
                cbResult <- liftGatewayIO $ withCircuitBreaker cb $ do
                    (provResult, _, _, _) <- runGatewayM (action p)
                    case provResult of
                        Success a -> pure $ Right a
                        Failure err -> pure $ Left err
                        Retry err -> pure $ Left err
                
                callEnd <- liftGatewayIO getCurrentTime
                let callLatencySeconds = realToFrac (diffUTCTime callEnd callStart) :: Double
                
                -- Capture circuit state AFTER the operation and emit event if changed
                stateAfter <- liftGatewayIO $ getCircuitState cb
                liftGatewayIO $ do
                    stats <- getCircuitStats cb
                    emitProviderStatusChange (routerEventBroadcaster router) pName stateBefore stateAfter stats
                
                case cbResult of
                    Left circuitOpenMsg -> do
                        -- Circuit is open, skip this provider
                        let err = ProviderUnavailable circuitOpenMsg
                        liftGatewayIO $ recordProviderError (routerMetrics router) pName err
                        withRetry $ go ps (Just err)
                    
                    Right (Left provErr) -> do
                        -- Provider returned error
                        liftGatewayIO $ recordProviderError (routerMetrics router) pName provErr
                        -- Circuit breaker already recorded the failure
                        pure $ Left provErr
                    
                    Right (Right a) -> do
                        -- Provider call succeeded, circuit breaker recorded success
                        -- Record latency for latency-based provider selection
                        liftGatewayIO $ recordProviderSuccess (routerMetrics router) pName callLatencySeconds
                        -- Record the successful provider in provenance
                        recordProvider (providerNameToText pName)
                        pure $ Right a
      where
        handleResult result remainingProviders = case result of
            Success a -> pure $ Right a
            Failure err -> pure $ Left err  -- Non-retryable
            Retry err -> withRetry $ go remainingProviders (Just err)

-- | Store request in history cache for audit trail
storeRequestHistory :: Router -> Text -> Text -> Maybe Text -> Either ProviderError a -> UTCTime -> IO ()
storeRequestHistory router reqId model providerText result startTime = do
    endTime <- getCurrentTime
    let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double
        success = either (const False) (const True) result
        timestamp = T.pack $ show startTime  -- TODO: proper ISO 8601 formatting
        providerName = providerText >>= textToProviderName
    
    let history = RequestHistory
            { rhRequestId = reqId
            , rhModel = model
            , rhProvider = providerName
            , rhSuccess = success
            , rhLatencyMs = latencyMs
            , rhTimestamp = timestamp
            }
    
    cacheInsert (routerRequestHistory router) reqId history


-- ════════════════════════════════════════════════════════════════════════════
--                                                  // observability accessors
-- ════════════════════════════════════════════════════════════════════════════

-- | Get current metrics snapshot
getRouterMetrics :: Router -> IO Metrics
getRouterMetrics = getMetrics . routerMetrics

-- | Get circuit breaker stats for all providers
getProviderCircuitStats :: Router -> IO [(ProviderName, CircuitStats)]
getProviderCircuitStats router = do
    stats <- mapM (\(name, cb) -> (,) name <$> getCircuitStats cb) 
                  (Map.toList $ routerCircuitBreakers router)
    pure stats

-- | Look up request history by ID
lookupRequestHistory :: Router -> Text -> IO (Maybe RequestHistory)
lookupRequestHistory router reqId = 
    cacheLookup (routerRequestHistory router) reqId


-- ════════════════════════════════════════════════════════════════════════════
--                                                       // sse event helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Emit proof.generated event from a DischargeProof
emitProofGeneratedFromProof :: EventBroadcaster -> Text -> DischargeProof -> IO ()
emitProofGeneratedFromProof bc requestId proof = do
    now <- getCurrentTime
    let coeffectNames = map coeffectToText (dpCoeffects proof)
        signed = maybe False (const True) (dpSignature proof)
        timestamp = T.pack $ show now
    emitProofGenerated bc requestId coeffectNames signed timestamp

-- | Convert ProviderError to text for SSE events
providerErrorToText :: ProviderError -> Text
providerErrorToText (AuthError msg) = "Auth: " <> msg
providerErrorToText (RateLimitError msg) = "Rate limit: " <> msg
providerErrorToText (QuotaExceededError msg) = "Quota exceeded: " <> msg
providerErrorToText (ModelNotFoundError msg) = "Model not found: " <> msg
providerErrorToText (ProviderUnavailable msg) = "Provider unavailable: " <> msg
providerErrorToText (InvalidRequestError msg) = "Invalid request: " <> msg
providerErrorToText (InternalError msg) = "Internal error: " <> msg
providerErrorToText (TimeoutError msg) = "Timeout: " <> msg
providerErrorToText (UnknownError msg) = "Unknown error: " <> msg

-- | Safe head that returns Nothing on empty list
safeHead :: [a] -> Maybe a
safeHead [] = Nothing
safeHead (x:_) = Just x

-- | Emit provider.status event when circuit breaker state changes
emitProviderStatusChange :: EventBroadcaster -> ProviderName -> CB.CircuitState -> CB.CircuitState -> CircuitStats -> IO ()
emitProviderStatusChange bc pName oldState newState stats
    | oldState == newState = pure ()  -- No change, don't emit
    | otherwise = do
        now <- getCurrentTime
        let timestamp = T.pack $ show now
            sseState = cbStateToSSE newState
            lastFailureTs = fmap (T.pack . show) (csLastFailure stats)
        emitProviderStatus bc (providerNameToText pName) sseState (csFailureCount stats) (cbcFailureThreshold defaultCircuitBreakerConfig) lastFailureTs timestamp

-- | Convert CircuitBreaker.CircuitState to Streaming.Events.CircuitState
cbStateToSSE :: CB.CircuitState -> CircuitState
cbStateToSSE CB.Closed = CircuitClosed
cbStateToSSE CB.Open = CircuitOpen
cbStateToSSE CB.HalfOpen = CircuitHalfOpen

-- | Convert ProviderName to Text
providerNameToText :: ProviderName -> Text
providerNameToText Venice = "venice"
providerNameToText Vertex = "vertex"
providerNameToText Baseten = "baseten"
providerNameToText OpenRouter = "openrouter"
providerNameToText Anthropic = "anthropic"

-- | Convert Text to ProviderName (for history storage)
textToProviderName :: Text -> Maybe ProviderName
textToProviderName "venice" = Just Venice
textToProviderName "vertex" = Just Vertex
textToProviderName "baseten" = Just Baseten
textToProviderName "openrouter" = Just OpenRouter
textToProviderName "anthropic" = Just Anthropic
textToProviderName _ = Nothing
