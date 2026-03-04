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
-- Priority: Triton (local) -> Venice -> Vertex -> Baseten -> OpenRouter -> Anthropic
--
-- Triton is first: local TensorRT-LLM inference (~50-200ms latency)
-- On failure, routes to next provider if error is retryable.
-- Non-retryable errors (auth, invalid request) fail immediately.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Router
  ( -- * Router
    Router (Router, routerManager, routerProviders, routerConfig, routerTritonConfig, routerTogetherConfig, routerSambanovaConfig, routerFireworksConfig, routerNovitaConfig, routerDeepInfraConfig, routerModalConfig, routerGroqConfig, routerCerebrasConfig, routerVeniceConfig, routerVertexConfig, routerBasetenConfig, routerOpenRouterConfig, routerAnthropicConfig, routerProofCache, routerModelRegistry, routerMetrics, routerBackpressure, routerCircuitBreakers, routerRequestHistory, routerAdminSemaphore, routerResponseCache, routerEventBroadcaster, routerMetricsCollector, routerModelIntelligence, routerSigilPublisher, routerDefaultModel),
    makeRouter,
    closeRouter,

    -- * Routing
    routeChat,
    routeChatStream,
    routeEmbeddings,
    routeModels,

    -- * Proof Access
    lookupProof,
    listRecentProofs,

    -- * Provider Chain
    ProviderChain,
    defaultChain,

    -- * Observability (for API endpoints)
    RequestHistory (RequestHistory, rhRequestId, rhModel, rhProvider, rhSuccess, rhLatencyMs, rhTimestamp),
    getRouterMetrics,
    getProviderCircuitStats,
    lookupRequestHistory,

    -- * SSE Events (re-export)
    EventBroadcaster,
    subscribe,
    encodeSSEEvent,

    -- * Model Intelligence (re-export for API handlers)
    ModelIntelligence,
    getModelSpec,
    getAllSpecs,
    getProviderSpecs,
    getNewModels,
    searchModels,
    ModelSpec (..),
    ModelCapabilities (..),
    ModelPricing (..),
    ModelModality (..),
    APIFormat (..),
    NewModelEvent (..),
  )
where

import Coeffect.Discharge (fromGatewayTracking)
import Coeffect.Types (DischargeProof, coeffectToText, dpCoeffects, dpSignature)
import Config
  ( Config
      ( cfgAnthropic,
        cfgBaseten,
        cfgCacheConfig,
        cfgCerebras,
        cfgDeepInfra,
        cfgFireworks,
        cfgGroq,
        cfgModal,
        cfgNovita,
        cfgOpenRouter,
        cfgPoolConfig,
        cfgRequestTimeout,
        cfgSambaNova,
        cfgSigil,
        cfgTogether,
        cfgTriton,
        cfgVenice,
        cfgVertex
      ),
    ConnectionPoolConfig (cpcConnectionsPerHost, cpcIdleConnections),
    ProviderConfig,
    ResponseCacheConfig (rccEnabled, rccMaxSize, rccTtlSeconds),
    SigilConfig (scBindAddress, scDefaultModel, scEnabled),
  )
import Data.Aeson (FromJSON (parseJSON), ToJSON (toJSON), encode, object, withObject, (.:), (.=))
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import Effects.Do qualified as G
import Effects.Graded (Full, GatewayM, gpProvidersUsed, liftIO', recordProvider, recordRequestId, runGatewayM, withRetry)
import Network.HTTP.Client qualified as HC
import Network.HTTP.Client.TLS qualified as HCT
import Provider.Anthropic (makeAnthropicProvider)
import Provider.Baseten (makeBasetenProvider)
-- Query functions (exposed for API handlers)

-- Types (needed for API responses)

-- Lifecycle

-- High-throughput providers (no rate limits, MoE optimized)

import Provider.Cerebras (makeCerebrasProvider)
import Provider.DeepInfra (makeDeepInfraProvider)
import Provider.Fireworks (makeFireworksProvider)
import Provider.Groq (makeGroqProvider)
import Provider.Modal (makeModalProvider)
import Provider.ModelIntelligence
  ( APIFormat (..),
    ModelCapabilities (..),
    ModelIntelligence,
    ModelModality (..),
    ModelPricing (..),
    ModelSpec (..),
    NewModelEvent (..),
    closeModelIntelligence,
    getAllSpecs,
    getModelSpec,
    getNewModels,
    getProviderSpecs,
    makeModelIntelligence,
    searchModels,
  )
import Provider.ModelRegistry (ModelRegistry, makeModelRegistry, registrySupportsModel)
import Provider.Novita (makeNovitaProvider)
import Provider.OpenRouter (makeOpenRouterProvider)
import Provider.SambaNova (makeSambaNovaProvider)
import Provider.Together (makeTogetherProvider)
import Provider.Triton (makeTritonProvider)
import Provider.Types
  ( Provider
      ( providerChat,
        providerChatStream,
        providerEmbeddings,
        providerEnabled,
        providerModels,
        providerName,
        providerSupportsModel
      ),
    ProviderError
      ( AuthError,
        InternalError,
        InvalidRequestError,
        ModelNotFoundError,
        ProviderUnavailable,
        QuotaExceededError,
        RateLimitError,
        TimeoutError,
        UnknownError
      ),
    ProviderName
      ( Anthropic,
        Baseten,
        Cerebras,
        DeepInfra,
        Fireworks,
        Groq,
        LambdaLabs,
        Modal,
        Novita,
        OpenRouter,
        RunPod,
        SambaNova,
        Together,
        Triton,
        VastAI,
        Venice,
        Vertex
      ),
    ProviderResult (Failure, Retry, Success),
    RequestContext (RequestContext, rcClientIp, rcManager, rcRequestId),
    StreamCallback,
  )
import Provider.Venice (makeVeniceProvider)
import Provider.Vertex (makeVertexProvider)
import Resilience.Backpressure (RequestSemaphore, newRequestSemaphore, tryWithRequestSlot)
import Resilience.Cache (BoundedCache, CacheConfig (ccMaxSize, ccTTL), cacheInsert, cacheLookup, defaultCacheConfig, newBoundedCache)
import Resilience.CircuitBreaker
  ( CircuitBreaker,
    CircuitBreakerConfig (cbcFailureThreshold),
    CircuitStats (csFailureCount, csLastFailure),
    defaultCircuitBreakerConfig,
    getCircuitState,
    getCircuitStats,
    newCircuitBreaker,
    withCircuitBreaker,
  )
import Resilience.CircuitBreaker qualified as CB
import Resilience.Metrics (Metrics, MetricsStore, getMetrics, getProviderLatencies, newMetricsStore, recordProviderError, recordProviderRequest, recordProviderSuccess, recordRequest, recordRequestComplete)
import Streaming.Events
  ( CircuitState (CircuitClosed, CircuitHalfOpen, CircuitOpen),
    EventBroadcaster,
    MetricsCollector,
    emitProofGenerated,
    emitProviderStatus,
    emitRequestCompleted,
    emitRequestStarted,
    encodeSSEEvent,
    newEventBroadcaster,
    newMetricsCollector,
    recordMetricsError,
    recordMetricsLatency,
    recordMetricsRequest,
    startMetricsLoop,
    subscribe,
  )
import Types

-- // SIGIL transport and model
import Slide.Model (loadModel)
import Slide.Model qualified as Slide
import Transport.Zmq (SigilPublisher, closeSigilPublisher, newSigilPublisher)

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
  { rhRequestId :: !Text,
    rhModel :: !Text,
    rhProvider :: !(Maybe ProviderName),
    rhSuccess :: !Bool,
    rhLatencyMs :: !Double,
    rhTimestamp :: !Text -- ISO 8601 timestamp
  }
  deriving (Eq, Show)

instance ToJSON RequestHistory where
  toJSON rh =
    object
      [ "request_id" .= rhRequestId rh,
        "model" .= rhModel rh,
        "provider" .= rhProvider rh,
        "success" .= rhSuccess rh,
        "latency_ms" .= rhLatencyMs rh,
        "timestamp" .= rhTimestamp rh
      ]

instance FromJSON RequestHistory where
  parseJSON = withObject "RequestHistory" $ \v ->
    RequestHistory
      <$> v .: "request_id"
      <*> v .: "model"
      <*> v .: "provider"
      <*> v .: "success"
      <*> v .: "latency_ms"
      <*> v .: "timestamp"

-- | Router state with full resilience infrastructure
data Router = Router
  { routerManager :: HC.Manager,
    routerProviders :: ProviderChain,
    routerConfig :: Config,
    -- Tier 1: Local inference
    routerTritonConfig :: IORef ProviderConfig, -- Local Triton/TensorRT-LLM (FIRST in chain)
    -- Tier 2: High-throughput providers (no rate limits, MoE optimized)
    routerTogetherConfig :: IORef ProviderConfig,
    routerSambanovaConfig :: IORef ProviderConfig,
    routerFireworksConfig :: IORef ProviderConfig,
    routerNovitaConfig :: IORef ProviderConfig,
    routerDeepInfraConfig :: IORef ProviderConfig,
    routerModalConfig :: IORef ProviderConfig,
    routerGroqConfig :: IORef ProviderConfig,
    routerCerebrasConfig :: IORef ProviderConfig,
    -- Tier 3: Standard providers
    routerVeniceConfig :: IORef ProviderConfig,
    routerVertexConfig :: IORef ProviderConfig,
    routerBasetenConfig :: IORef ProviderConfig,
    routerOpenRouterConfig :: IORef ProviderConfig,
    routerAnthropicConfig :: IORef ProviderConfig, -- Direct Anthropic API (last in chain)
    routerProofCache :: IORef ProofCache,
    routerModelRegistry :: ModelRegistry, -- Dynamic model registry with sync

    -- Resilience infrastructure (billion-agent scale)
    routerMetrics :: MetricsStore, -- Prometheus-style metrics
    routerBackpressure :: RequestSemaphore, -- Limit concurrent requests
    routerCircuitBreakers :: Map ProviderName CircuitBreaker, -- One per provider
    routerRequestHistory :: BoundedCache Text RequestHistory, -- Audit trail
    routerAdminSemaphore :: RequestSemaphore, -- Rate limit admin endpoints

    -- Response cache (for identical queries - billion-agent optimization)
    routerResponseCache :: BoundedCache LBS.ByteString ChatResponse, -- Hash of request -> response

    -- Real-time event broadcasting (SSE)
    routerEventBroadcaster :: EventBroadcaster, -- SSE event broadcaster
    routerMetricsCollector :: MetricsCollector, -- Rolling window metrics for SSE emission

    -- Model intelligence (specs, new model detection, capabilities)
    routerModelIntelligence :: ModelIntelligence,

    -- SIGIL frame egress (ZMQ PUB socket)
    routerSigilPublisher :: Maybe SigilPublisher, -- Nothing if SIGIL disabled
    routerDefaultModel :: Slide.Model -- Default model for tokenization
  }

-- | Default provider chain order
-- Triton is first: local TensorRT-LLM inference (~50-200ms latency)
-- Anthropic is last: direct API access, used when explicitly requested or all others fail
defaultChain :: [ProviderName]
defaultChain = [Triton, Venice, Vertex, Baseten, OpenRouter, Anthropic]

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // construction
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a router from config
makeRouter :: Config -> IO Router
makeRouter config = do
  -- Create HTTP manager optimized for high-throughput billion-agent scale
  -- Configurable via POOL_CONNECTIONS_PER_HOST, POOL_IDLE_CONNECTIONS, POOL_IDLE_TIMEOUT_SECONDS
  let poolConf = cfgPoolConfig config
      settings =
        HCT.tlsManagerSettings
          { HC.managerResponseTimeout =
              HC.responseTimeoutMicro (cfgRequestTimeout config * 1000000),
            -- Connection pool size per host (configurable, default 100)
            HC.managerConnCount = cpcConnectionsPerHost poolConf,
            -- Idle connection pool limit (configurable, default 200)
            HC.managerIdleConnectionCount = cpcIdleConnections poolConf
            -- Note: managerIdleConnectionCount is total idle connections, not timeout
            -- http-client doesn't expose idle timeout directly in ManagerSettings
          }
  manager <- HC.newManager settings

  -- Create config refs (allows runtime updates)
  -- Tier 1: Local inference
  tritonRef <- newIORef (cfgTriton config)
  -- Tier 2: High-throughput providers (no rate limits, MoE optimized)
  togetherRef <- newIORef (cfgTogether config)
  sambanovaRef <- newIORef (cfgSambaNova config)
  fireworksRef <- newIORef (cfgFireworks config)
  novitaRef <- newIORef (cfgNovita config)
  deepinfraRef <- newIORef (cfgDeepInfra config)
  modalRef <- newIORef (cfgModal config)
  groqRef <- newIORef (cfgGroq config)
  cerebrasRef <- newIORef (cfgCerebras config)
  -- Tier 3: Standard providers
  veniceRef <- newIORef (cfgVenice config)
  vertexRef <- newIORef (cfgVertex config)
  basetenRef <- newIORef (cfgBaseten config)
  openrouterRef <- newIORef (cfgOpenRouter config)
  anthropicRef <- newIORef (cfgAnthropic config)

  -- Create providers
  -- Tier 1: Local inference (zero cost)
  let tritonProvider = makeTritonProvider tritonRef

  -- Tier 2: High-throughput providers (MoE optimized, no/flexible rate limits)
  -- These are preferred for billion-agent scale due to throughput
  let togetherProvider = makeTogetherProvider togetherRef
  let sambanovaProvider = makeSambaNovaProvider sambanovaRef
  let fireworksProvider = makeFireworksProvider fireworksRef
  let novitaProvider = makeNovitaProvider novitaRef
  let deepinfraProvider = makeDeepInfraProvider deepinfraRef
  let modalProvider = makeModalProvider modalRef
  let groqProvider = makeGroqProvider groqRef
  let cerebrasProvider = makeCerebrasProvider cerebrasRef

  -- Tier 3: Standard providers
  let veniceProvider = makeVeniceProvider veniceRef
  vertexProvider <- makeVertexProvider vertexRef
  let basetenProvider = makeBasetenProvider basetenRef
  let openrouterProvider = makeOpenRouterProvider openrouterRef
  let anthropicProvider = makeAnthropicProvider anthropicRef

  -- Build chain in priority order for billion-agent scale:
  -- 1. Triton first for local inference (fastest, no cost)
  -- 2. High-throughput MoE providers (SambaNova, Novita, Groq, Cerebras - insane speed)
  -- 3. Other high-throughput (Together, Fireworks, DeepInfra)
  -- 4. Modal for burst capacity
  -- 5. Standard providers (Venice, Vertex, Baseten)
  -- 6. Anthropic for Claude models (direct API access)
  -- 7. OpenRouter LAST as universal fallback (aggregator)
  let providers =
        [ tritonProvider,
          -- Tier 2: High-throughput (prioritize by speed/throughput)
          sambanovaProvider, -- RDU hardware, massive throughput
          novitaProvider, -- NO rate limits
          groqProvider, -- LPU hardware, insane speed
          cerebrasProvider, -- Wafer-scale inference
          togetherProvider, -- Fast open models
          fireworksProvider, -- Optimized inference
          deepinfraProvider, -- Good coverage
          modalProvider, -- Burst capacity
          -- Tier 3: Standard providers
          veniceProvider,
          vertexProvider,
          basetenProvider,
          anthropicProvider, -- Direct Anthropic API
          openrouterProvider -- Universal fallback (aggregator)
        ]

  -- Create proof cache
  proofCacheRef <- newIORef Map.empty

  -- Create model registry with 5-minute sync interval
  modelRegistry <- makeModelRegistry manager providers 300

  -- Initialize resilience infrastructure for billion-agent scale
  metricsStore <- newMetricsStore

  -- Backpressure: limit to 10000 concurrent requests (prevent OOM)
  backpressure <- newRequestSemaphore 10000

  -- Circuit breakers: one per provider
  -- Tier 1
  tritonCB <- newCircuitBreaker "triton" defaultCircuitBreakerConfig
  -- Tier 2: High-throughput
  togetherCB <- newCircuitBreaker "together" defaultCircuitBreakerConfig
  sambanovaCB <- newCircuitBreaker "sambanova" defaultCircuitBreakerConfig
  fireworksCB <- newCircuitBreaker "fireworks" defaultCircuitBreakerConfig
  novitaCB <- newCircuitBreaker "novita" defaultCircuitBreakerConfig
  deepinfraCB <- newCircuitBreaker "deepinfra" defaultCircuitBreakerConfig
  modalCB <- newCircuitBreaker "modal" defaultCircuitBreakerConfig
  groqCB <- newCircuitBreaker "groq" defaultCircuitBreakerConfig
  cerebrasCB <- newCircuitBreaker "cerebras" defaultCircuitBreakerConfig
  -- Tier 3
  veniceCB <- newCircuitBreaker "venice" defaultCircuitBreakerConfig
  vertexCB <- newCircuitBreaker "vertex" defaultCircuitBreakerConfig
  basetenCB <- newCircuitBreaker "baseten" defaultCircuitBreakerConfig
  openrouterCB <- newCircuitBreaker "openrouter" defaultCircuitBreakerConfig
  anthropicCB <- newCircuitBreaker "anthropic" defaultCircuitBreakerConfig

  let circuitBreakers =
        Map.fromList
          [ -- Tier 1
            (Triton, tritonCB),
            -- Tier 2: High-throughput
            (Together, togetherCB),
            (SambaNova, sambanovaCB),
            (Fireworks, fireworksCB),
            (Novita, novitaCB),
            (DeepInfra, deepinfraCB),
            (Modal, modalCB),
            (Groq, groqCB),
            (Cerebras, cerebrasCB),
            -- Tier 3
            (Venice, veniceCB),
            (Vertex, vertexCB),
            (Baseten, basetenCB),
            (OpenRouter, openrouterCB),
            (Anthropic, anthropicCB)
          ]

  -- Request history cache (5000 most recent requests for audit)
  requestHistory <- newBoundedCache defaultCacheConfig {ccMaxSize = 5000}

  -- Admin endpoint rate limiting (10 concurrent requests max)
  adminSemaphore <- newRequestSemaphore 10

  -- Response cache for identical queries (billion-agent optimization)
  -- Configurable via CACHE_ENABLED, CACHE_MAX_SIZE, CACHE_TTL_SECONDS
  let cacheConf = cfgCacheConfig config
  responseCache <-
    newBoundedCache
      defaultCacheConfig
        { ccMaxSize = rccMaxSize cacheConf,
          ccTTL = Just (fromIntegral (rccTtlSeconds cacheConf))
        }

  -- Event broadcaster for SSE real-time updates
  eventBroadcaster <- newEventBroadcaster

  -- Metrics collector for SSE emission (rolling 10-second window)
  metricsCollector <- newMetricsCollector

  -- Start the metrics emission loop (broadcasts every 10 seconds)
  _ <- startMetricsLoop eventBroadcaster metricsCollector

  -- Model intelligence system (specs, new model detection, capabilities)
  -- Syncs every 5 minutes to detect new models across providers
  modelIntelligence <- makeModelIntelligence manager providers eventBroadcaster 300

  -- SIGIL egress: ZMQ PUB socket for SIGIL frame emission
  let sigilConf = cfgSigil config
  sigilPublisher <-
    if scEnabled sigilConf
      then Just <$> newSigilPublisher (scBindAddress sigilConf)
      else pure Nothing

  -- Load default model for tokenization
  defaultModel <- loadModel (scDefaultModel sigilConf)

  pure
    Router
      { routerManager = manager,
        routerProviders = providers,
        routerConfig = config,
        -- Tier 1
        routerTritonConfig = tritonRef,
        -- Tier 2: High-throughput
        routerTogetherConfig = togetherRef,
        routerSambanovaConfig = sambanovaRef,
        routerFireworksConfig = fireworksRef,
        routerNovitaConfig = novitaRef,
        routerDeepInfraConfig = deepinfraRef,
        routerModalConfig = modalRef,
        routerGroqConfig = groqRef,
        routerCerebrasConfig = cerebrasRef,
        -- Tier 3
        routerVeniceConfig = veniceRef,
        routerVertexConfig = vertexRef,
        routerBasetenConfig = basetenRef,
        routerOpenRouterConfig = openrouterRef,
        routerAnthropicConfig = anthropicRef,
        routerProofCache = proofCacheRef,
        routerModelRegistry = modelRegistry,
        routerMetrics = metricsStore,
        routerBackpressure = backpressure,
        routerCircuitBreakers = circuitBreakers,
        routerRequestHistory = requestHistory,
        routerAdminSemaphore = adminSemaphore,
        routerResponseCache = responseCache,
        routerEventBroadcaster = eventBroadcaster,
        routerMetricsCollector = metricsCollector,
        routerModelIntelligence = modelIntelligence,
        routerSigilPublisher = sigilPublisher,
        routerDefaultModel = defaultModel
      }

-- | Gracefully shutdown router and release all resources
-- This MUST be called when the server shuts down to avoid resource leaks
closeRouter :: Router -> IO ()
closeRouter router = do
  -- Stop model intelligence sync thread
  closeModelIntelligence (routerModelIntelligence router)

  -- Close SIGIL publisher if enabled
  case routerSigilPublisher router of
    Just publisher -> closeSigilPublisher publisher
    Nothing -> pure ()

-- Note: ModelRegistry also has a sync thread we should close
-- TODO: Add closeModelRegistry when implementing full cleanup

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
  let cacheConf = cfgCacheConfig (routerConfig router)
      cacheKey = encode req -- JSON encoding as cache key
      isCacheable =
        rccEnabled cacheConf
          && (crTemperature req == Just (Temperature 0) || crSeed req /= Nothing)

  cachedResponse <-
    if isCacheable
      then cacheLookup (routerResponseCache router) cacheKey
      else pure Nothing

  case cachedResponse of
    Just resp -> do
      -- Cache hit! Return immediately
      recordRequestComplete (routerMetrics router) startTime
      endTime <- getCurrentTime
      let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double
          endTimestamp = T.pack $ show endTime
      -- Record metrics for SSE (success case, cached)
      recordMetricsRequest (routerMetricsCollector router)
      recordMetricsLatency (routerMetricsCollector router) latencyMs
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
        (result, _grade, prov, coeff) <- runGatewayM $ G.do
          recordRequestId requestId
          let ctx =
                RequestContext
                  { rcManager = routerManager router,
                    rcRequestId = requestId,
                    rcClientIp = Nothing
                  }

          -- Find enabled providers from the pre-ordered list
          enabledProviders <- filterEnabledProviders orderedProviders

          -- Try each provider with circuit breakers
          tryProvidersWithCircuitBreakers router enabledProviders $ \provider ->
            providerChat provider ctx req

        -- Cache successful responses for cacheable requests
        case result of
          Right resp
            | isCacheable ->
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
          -- Record metrics for SSE (error case)
          recordMetricsRequest (routerMetricsCollector router)
          recordMetricsError (routerMetricsCollector router)
          recordMetricsLatency (routerMetricsCollector router) latencyMs
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

          -- Record metrics for SSE emission (rolling window)
          recordMetricsRequest (routerMetricsCollector router)
          recordMetricsLatency (routerMetricsCollector router) latencyMs
          case result of
            Left _ -> recordMetricsError (routerMetricsCollector router)
            Right _ -> pure ()

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

    (result, _grade, prov, coeff) <- runGatewayM $ G.do
      recordRequestId requestId
      let ctx =
            RequestContext
              { rcManager = routerManager router,
                rcRequestId = requestId,
                rcClientIp = Nothing
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
      -- Record metrics for SSE (error case)
      recordMetricsRequest (routerMetricsCollector router)
      recordMetricsError (routerMetricsCollector router)
      recordMetricsLatency (routerMetricsCollector router) latencyMs
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

      -- Record metrics for SSE emission (rolling window)
      recordMetricsRequest (routerMetricsCollector router)
      recordMetricsLatency (routerMetricsCollector router) latencyMs
      case result of
        Left _ -> recordMetricsError (routerMetricsCollector router)
        Right _ -> pure ()

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
    (result, _grade, prov, coeff) <- runGatewayM $ G.do
      recordRequestId requestId
      let ctx =
            RequestContext
              { rcManager = routerManager router,
                rcRequestId = requestId,
                rcClientIp = Nothing
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
      -- Record metrics for SSE (error case)
      recordMetricsRequest (routerMetricsCollector router)
      recordMetricsError (routerMetricsCollector router)
      recordMetricsLatency (routerMetricsCollector router) latencyMs
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

      -- Record metrics for SSE emission (rolling window)
      recordMetricsRequest (routerMetricsCollector router)
      recordMetricsLatency (routerMetricsCollector router) latencyMs
      case result of
        Left _ -> recordMetricsError (routerMetricsCollector router)
        Right _ -> pure ()

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
    (result, _grade, prov, coeff) <- runGatewayM $ G.do
      recordRequestId requestId
      let ctx =
            RequestContext
              { rcManager = routerManager router,
                rcRequestId = requestId,
                rcClientIp = Nothing
              }

      enabledProviders <- filterEnabledProviders (routerProviders router)

      -- Collect models from all providers (no circuit breaker for this read-only op)
      -- Use collectModels helper to work around graded monad constraints
      collectModels ctx enabledProviders

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
      -- Record metrics for SSE (error case)
      recordMetricsRequest (routerMetricsCollector router)
      recordMetricsError (routerMetricsCollector router)
      recordMetricsLatency (routerMetricsCollector router) latencyMs
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

      -- Record metrics for SSE emission (rolling window)
      recordMetricsRequest (routerMetricsCollector router)
      recordMetricsLatency (routerMetricsCollector router) latencyMs
      case result of
        Left _ -> recordMetricsError (routerMetricsCollector router)
        Right _ -> pure ()

      -- Store in request history for audit (with provider)
      storeRequestHistory router requestId modelType provider result startTime

      emitRequestCompleted (routerEventBroadcaster router) requestId modelType provider success latencyMs errMsg endTimestamp

      pure result

-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Filter to only enabled providers
filterEnabledProviders :: [Provider] -> GatewayM Full [Provider]
filterEnabledProviders [] = liftIO' $ pure []
filterEnabledProviders (p : ps) = G.do
  enabled <- providerEnabled p
  rest <- filterEnabledProviders ps
  liftIO' $ pure $ if enabled then p : rest else rest

-- | Collect models from all providers
collectModels :: RequestContext -> [Provider] -> GatewayM Full (Either ProviderError ModelList)
collectModels _ctx [] = liftIO' $ pure $ Left $ ProviderUnavailable "No providers available"
collectModels ctx providers = G.do
  results <- collectModelsAcc ctx providers []
  let successModels = concatMap extractModelsFromResult results
  if null successModels
    then liftIO' $ pure $ Left $ ProviderUnavailable "No providers available"
    else liftIO' $ pure $ Right $ ModelList "list" successModels
  where
    extractModelsFromResult (Success (ModelList _ models)) = models
    extractModelsFromResult _ = []

-- | Accumulate model results from providers
collectModelsAcc :: RequestContext -> [Provider] -> [ProviderResult ModelList] -> GatewayM Full [ProviderResult ModelList]
collectModelsAcc _ctx [] acc = liftIO' $ pure (reverse acc)
collectModelsAcc ctx (p : ps) acc = G.do
  result <- providerModels p ctx
  collectModelsAcc ctx ps (result : acc)

-- | Partition providers by whether they support a given model
-- Uses the model registry for dynamic model support (fetched from provider APIs)
-- Returns providers ordered: supporting first, then others
partitionByModelSupport :: ModelRegistry -> Text -> [Provider] -> IO [Provider]
partitionByModelSupport registry modelId providers = do
  -- Check each provider against the registry first, then fall back to provider's own check
  supported <- mapM checkSupport providers
  let (supporting, others) = foldr classify ([], []) (zip providers supported)
  -- ONLY return supporting providers - don't try providers that don't support the model
  pure $ if null supporting then others else supporting
  where
    checkSupport p = do
      registrySupport <- registrySupportsModel registry (providerName p) modelId
      -- Also check provider's own supportsModel as fallback
      let providerSupport = providerSupportsModel p modelId
      pure $ registrySupport || providerSupport
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
    insertByLatency lm p (q : qs) =
      let pLat = Map.findWithDefault maxLatency (providerName p) lm
          qLat = Map.findWithDefault maxLatency (providerName q) lm
       in if pLat <= qLat then p : q : qs else q : insertByLatency lm p qs
    maxLatency = 1000.0 :: Double -- 1000 seconds = effectively infinite

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // proof management
-- ════════════════════════════════════════════════════════════════════════════

-- | Store a proof in the cache, evicting oldest if over capacity
storeProof :: Router -> Text -> DischargeProof -> IO ()
storeProof router requestId proof =
  atomicModifyIORef' (routerProofCache router) $ \cache ->
    let cache' = Map.insert requestId proof cache
        -- Evict oldest entries if over capacity
        trimmed =
          if Map.size cache' > maxProofCache
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
tryProvidersWithCircuitBreakers :: Router -> [Provider] -> (Provider -> GatewayM Full (ProviderResult a)) -> GatewayM Full (Either ProviderError a)
tryProvidersWithCircuitBreakers router providers action = go providers Nothing
  where
    go [] lastErr = liftIO' $ pure $ Left $ maybe (ProviderUnavailable "All providers failed") id lastErr
    go (p : ps) _lastErr = G.do
      let pName = providerName p

      -- Record provider request in metrics
      liftIO' $ recordProviderRequest (routerMetrics router) pName

      -- Get circuit breaker for this provider
      tryProviderWithCB router p ps action (Map.lookup pName (routerCircuitBreakers router))

-- | Try a single provider with circuit breaker
tryProviderWithCB :: Router -> Provider -> [Provider] -> (Provider -> GatewayM Full (ProviderResult a)) -> Maybe CircuitBreaker -> GatewayM Full (Either ProviderError a)
tryProviderWithCB _router p ps action Nothing = G.do
  -- No circuit breaker (shouldn't happen, but handle gracefully)
  result <- action p
  handleProviderResult result ps
  where
    handleProviderResult result remainingProviders = case result of
      Success a -> liftIO' $ pure $ Right a
      Failure err -> liftIO' $ pure $ Left err -- Non-retryable
      Retry _err -> withRetry $ tryProvidersWithCircuitBreakers _router remainingProviders action
tryProviderWithCB router p ps action (Just cb) = G.do
  let pName = providerName p

  -- Capture circuit state BEFORE the operation
  stateBefore <- liftIO' $ getCircuitState cb

  -- Time the provider call for latency tracking
  callStart <- liftIO' getCurrentTime

  -- Check circuit breaker - need to convert ProviderResult to Either for circuit breaker
  cbResult <- liftIO' $ withCircuitBreaker cb $ do
    (provResult, _, _, _) <- runGatewayM (action p)
    case provResult of
      Success a -> pure $ Right a
      Failure err -> pure $ Left err
      Retry err -> pure $ Left err

  callEnd <- liftIO' getCurrentTime
  let callLatencySeconds = realToFrac (diffUTCTime callEnd callStart) :: Double

  -- Capture circuit state AFTER the operation and emit event if changed
  stateAfter <- liftIO' $ getCircuitState cb
  liftIO' $ do
    stats <- getCircuitStats cb
    emitProviderStatusChange (routerEventBroadcaster router) pName stateBefore stateAfter stats

  handleCBResult router pName ps action cbResult callLatencySeconds

-- | Handle circuit breaker result
handleCBResult :: Router -> ProviderName -> [Provider] -> (Provider -> GatewayM Full (ProviderResult a)) -> Either Text (Either ProviderError a) -> Double -> GatewayM Full (Either ProviderError a)
handleCBResult router pName ps action cbResult callLatencySeconds =
  case cbResult of
    Left circuitOpenMsg -> G.do
      -- Circuit is open, skip this provider
      let err = ProviderUnavailable circuitOpenMsg
      liftIO' $ recordProviderError (routerMetrics router) pName err
      withRetry $ tryProvidersWithCircuitBreakers router ps action
    Right (Left provErr) -> G.do
      -- Provider returned error
      liftIO' $ recordProviderError (routerMetrics router) pName provErr
      -- Circuit breaker already recorded the failure
      liftIO' $ pure $ Left provErr
    Right (Right a) -> G.do
      -- Provider call succeeded, circuit breaker recorded success
      -- Record latency for latency-based provider selection
      liftIO' $ recordProviderSuccess (routerMetrics router) pName callLatencySeconds
      -- Record the successful provider in provenance
      recordProvider (providerNameToText pName)
      liftIO' $ pure $ Right a

-- | Store request in history cache for audit trail
storeRequestHistory :: Router -> Text -> Text -> Maybe Text -> Either ProviderError a -> UTCTime -> IO ()
storeRequestHistory router reqId model providerText result startTime = do
  endTime <- getCurrentTime
  let latencyMs = realToFrac (diffUTCTime endTime startTime) * 1000 :: Double
      success = either (const False) (const True) result
      timestamp = T.pack $ show startTime -- TODO: proper ISO 8601 formatting
      providerName = providerText >>= textToProviderName

  let history =
        RequestHistory
          { rhRequestId = reqId,
            rhModel = model,
            rhProvider = providerName,
            rhSuccess = success,
            rhLatencyMs = latencyMs,
            rhTimestamp = timestamp
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
  stats <-
    mapM
      (\(name, cb) -> (,) name <$> getCircuitStats cb)
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
safeHead (x : _) = Just x

-- | Emit provider.status event when circuit breaker state changes
emitProviderStatusChange :: EventBroadcaster -> ProviderName -> CB.CircuitState -> CB.CircuitState -> CircuitStats -> IO ()
emitProviderStatusChange bc pName oldState newState stats
  | oldState == newState = pure () -- No change, don't emit
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
providerNameToText Triton = "triton"
-- Tier 2: High-throughput
providerNameToText Together = "together"
providerNameToText SambaNova = "sambanova"
providerNameToText Fireworks = "fireworks"
providerNameToText Novita = "novita"
providerNameToText DeepInfra = "deepinfra"
providerNameToText Modal = "modal"
providerNameToText Groq = "groq"
providerNameToText Cerebras = "cerebras"
-- Tier 3
providerNameToText Venice = "venice"
providerNameToText Vertex = "vertex"
providerNameToText Baseten = "baseten"
providerNameToText OpenRouter = "openrouter"
providerNameToText Anthropic = "anthropic"
-- Tier 4: GPU rate providers
providerNameToText LambdaLabs = "lambdalabs"
providerNameToText RunPod = "runpod"
providerNameToText VastAI = "vastai"

-- | Convert Text to ProviderName (for history storage)
textToProviderName :: Text -> Maybe ProviderName
textToProviderName "triton" = Just Triton
-- Tier 2: High-throughput
textToProviderName "together" = Just Together
textToProviderName "sambanova" = Just SambaNova
textToProviderName "fireworks" = Just Fireworks
textToProviderName "novita" = Just Novita
textToProviderName "deepinfra" = Just DeepInfra
textToProviderName "modal" = Just Modal
textToProviderName "groq" = Just Groq
textToProviderName "cerebras" = Just Cerebras
-- Tier 3
textToProviderName "venice" = Just Venice
textToProviderName "vertex" = Just Vertex
textToProviderName "baseten" = Just Baseten
textToProviderName "openrouter" = Just OpenRouter
textToProviderName "anthropic" = Just Anthropic
-- Tier 4: GPU rate providers
textToProviderName "lambdalabs" = Just LambdaLabs
textToProviderName "runpod" = Just RunPod
textToProviderName "vastai" = Just VastAI
textToProviderName _ = Nothing
