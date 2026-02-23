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
      Router (..)
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
    ) where

import Data.Aeson (encode)
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, newIORef, readIORef, atomicModifyIORef')
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)

import Network.HTTP.Client qualified as HC
import Network.HTTP.Client.TLS qualified as HCT

import Coeffect.Discharge (fromGatewayTracking)
import Coeffect.Types (DischargeProof)
import Config
import Effects.Graded
import Provider.Types
import Provider.Venice (makeVeniceProvider)
import Provider.Vertex (makeVertexProvider)
import Provider.Baseten (makeBasetenProvider)
import Provider.OpenRouter (makeOpenRouterProvider)
import Provider.Anthropic (makeAnthropicProvider)
import Provider.ModelRegistry (ModelRegistry, makeModelRegistry, registrySupportsModel)
import Types


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

-- | Router state
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
    -- Create HTTP manager with timeout
    let settings = HCT.tlsManagerSettings
            { HC.managerResponseTimeout =
                HC.responseTimeoutMicro (cfgRequestTimeout config * 1000000)
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
        }


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // routing
-- ════════════════════════════════════════════════════════════════════════════

-- | Route a chat completion request through the provider chain
routeChat :: Router -> Text -> ChatRequest -> IO (Either ProviderError ChatResponse)
routeChat router requestId req = do
    let modelId = unModelId $ crModel req
    
    -- Partition providers by model support (uses registry)
    orderedProviders <- partitionByModelSupport (routerModelRegistry router) modelId (routerProviders router)
    
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

        -- Try each provider in order
        tryProviders enabledProviders $ \provider ->
            providerChat provider ctx req
    
    -- Generate discharge proof
    let reqBody = LBS.toStrict $ encode req
        respBody = either (const "") (LBS.toStrict . encode) result
    proof <- fromGatewayTracking prov coeff reqBody respBody
    
    -- Store proof in cache
    storeProof router requestId proof
    
    pure result

-- | Route a streaming chat completion through the provider chain
routeChatStream :: Router -> Text -> ChatRequest -> StreamCallback -> IO (Either ProviderError ())
routeChatStream router requestId req callback = do
    let modelId = unModelId $ crModel req
    
    -- Partition providers by model support (uses registry)
    orderedProviders <- partitionByModelSupport (routerModelRegistry router) modelId (routerProviders router)
    
    -- Run the computation and capture tracking
    (result, _grade, prov, coeff) <- runGatewayM $ do
        recordRequestId requestId
        let ctx = RequestContext
                { rcManager = routerManager router
                , rcRequestId = requestId
                , rcClientIp = Nothing
                }

        enabledProviders <- filterEnabledProviders orderedProviders

        tryProviders enabledProviders $ \provider ->
            providerChatStream provider ctx req callback
    
    -- Generate discharge proof (streaming has no response body to hash)
    let reqBody = LBS.toStrict $ encode req
    proof <- fromGatewayTracking prov coeff reqBody ""
    
    -- Store proof in cache
    storeProof router requestId proof
    
    pure result

-- | Route an embeddings request through the provider chain
routeEmbeddings :: Router -> Text -> EmbeddingRequest -> IO (Either ProviderError EmbeddingResponse)
routeEmbeddings router requestId req = do
    -- Run the computation and capture tracking
    (result, _grade, prov, coeff) <- runGatewayM $ do
        recordRequestId requestId
        let ctx = RequestContext
                { rcManager = routerManager router
                , rcRequestId = requestId
                , rcClientIp = Nothing
                }

        enabledProviders <- filterEnabledProviders (routerProviders router)

        tryProviders enabledProviders $ \provider ->
            providerEmbeddings provider ctx req
    
    -- Generate discharge proof
    let reqBody = LBS.toStrict $ encode req
        respBody = either (const "") (LBS.toStrict . encode) result
    proof <- fromGatewayTracking prov coeff reqBody respBody
    
    -- Store proof in cache
    storeProof router requestId proof
    
    pure result

-- | Get models from all enabled providers
routeModels :: Router -> Text -> IO (Either ProviderError ModelList)
routeModels router requestId = do
    -- Run the computation and capture tracking
    (result, _grade, prov, coeff) <- runGatewayM $ do
        recordRequestId requestId
        let ctx = RequestContext
                { rcManager = routerManager router
                , rcRequestId = requestId
                , rcClientIp = Nothing
                }

        enabledProviders <- filterEnabledProviders (routerProviders router)

        -- Collect models from all providers
        results <- mapM (\p -> providerModels p ctx) enabledProviders

        -- Merge successful model lists
        let successModels = concatMap extractModels results

        if null successModels
            then pure $ Left $ ProviderUnavailable "No providers available"
            else pure $ Right $ ModelList "list" successModels
    
    -- Generate discharge proof (models endpoint has no request body)
    let respBody = either (const "") (LBS.toStrict . encode) result
    proof <- fromGatewayTracking prov coeff "" respBody
    
    -- Store proof in cache
    storeProof router requestId proof
    
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

-- | Try providers in order until one succeeds or all fail
tryProviders :: [Provider] -> (Provider -> GatewayM (ProviderResult a)) -> GatewayM (Either ProviderError a)
tryProviders [] _ = pure $ Left $ ProviderUnavailable "No providers configured"
tryProviders providers action = go providers Nothing
  where
    go [] lastErr = pure $ Left $ maybe (ProviderUnavailable "All providers failed") id lastErr
    go (p:ps) _lastErr = do
        result <- action p
        case result of
            Success a -> pure $ Right a
            Failure err -> pure $ Left err  -- Non-retryable, fail immediately
            Retry err -> withRetry $ go ps (Just err)   -- Retryable, try next provider


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
