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

      -- * Provider Chain
    , ProviderChain
    , defaultChain
    ) where

import Data.IORef (IORef, newIORef)
import Data.Text (Text)

import Network.HTTP.Client qualified as HC
import Network.HTTP.Client.TLS qualified as HCT

import Config
import Provider.Types
import Provider.Venice (makeVeniceProvider)
import Provider.Vertex (makeVertexProvider)
import Provider.Baseten (makeBasetenProvider)
import Provider.OpenRouter (makeOpenRouterProvider)
import Types


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Provider chain (ordered list of providers to try)
type ProviderChain = [Provider]

-- | Router state
data Router = Router
    { routerManager :: HC.Manager
    , routerProviders :: ProviderChain
    , routerConfig :: Config
    , routerVeniceConfig :: IORef ProviderConfig
    , routerVertexConfig :: IORef ProviderConfig
    , routerBasetenConfig :: IORef ProviderConfig
    , routerOpenRouterConfig :: IORef ProviderConfig
    }

-- | Default provider chain order
defaultChain :: [ProviderName]
defaultChain = [Venice, Vertex, Baseten, OpenRouter]


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

    -- Create providers
    let veniceProvider = makeVeniceProvider veniceRef
    vertexProvider <- makeVertexProvider vertexRef
    let basetenProvider = makeBasetenProvider basetenRef
    let openrouterProvider = makeOpenRouterProvider openrouterRef

    -- Build chain in priority order
    let providers = [veniceProvider, vertexProvider, basetenProvider, openrouterProvider]

    pure Router
        { routerManager = manager
        , routerProviders = providers
        , routerConfig = config
        , routerVeniceConfig = veniceRef
        , routerVertexConfig = vertexRef
        , routerBasetenConfig = basetenRef
        , routerOpenRouterConfig = openrouterRef
        }


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // routing
-- ════════════════════════════════════════════════════════════════════════════

-- | Route a chat completion request through the provider chain
routeChat :: Router -> Text -> ChatRequest -> IO (Either ProviderError ChatResponse)
routeChat router requestId req = do
    let ctx = RequestContext
            { rcManager = routerManager router
            , rcRequestId = requestId
            , rcClientIp = Nothing
            }

    -- Find enabled providers
    enabledProviders <- filterEnabledProviders (routerProviders router)

    -- Try each provider in order
    tryProviders enabledProviders $ \provider ->
        providerChat provider ctx req

-- | Route a streaming chat completion through the provider chain
routeChatStream :: Router -> Text -> ChatRequest -> StreamCallback -> IO (Either ProviderError ())
routeChatStream router requestId req callback = do
    let ctx = RequestContext
            { rcManager = routerManager router
            , rcRequestId = requestId
            , rcClientIp = Nothing
            }

    enabledProviders <- filterEnabledProviders (routerProviders router)

    tryProviders enabledProviders $ \provider ->
        providerChatStream provider ctx req callback

-- | Route an embeddings request through the provider chain
routeEmbeddings :: Router -> Text -> EmbeddingRequest -> IO (Either ProviderError EmbeddingResponse)
routeEmbeddings router requestId req = do
    let ctx = RequestContext
            { rcManager = routerManager router
            , rcRequestId = requestId
            , rcClientIp = Nothing
            }

    enabledProviders <- filterEnabledProviders (routerProviders router)

    tryProviders enabledProviders $ \provider ->
        providerEmbeddings provider ctx req

-- | Get models from all enabled providers
routeModels :: Router -> Text -> IO (Either ProviderError ModelList)
routeModels router requestId = do
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
  where
    extractModels (Success (ModelList _ models)) = models
    extractModels _ = []


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Filter to only enabled providers
filterEnabledProviders :: [Provider] -> IO [Provider]
filterEnabledProviders providers = do
    enabled <- mapM (\p -> (,) p <$> providerEnabled p) providers
    pure [p | (p, True) <- enabled]

-- | Try providers in order until one succeeds or all fail
tryProviders :: [Provider] -> (Provider -> IO (ProviderResult a)) -> IO (Either ProviderError a)
tryProviders [] _ = pure $ Left $ ProviderUnavailable "No providers configured"
tryProviders providers action = go providers Nothing
  where
    go [] lastErr = pure $ Left $ maybe (ProviderUnavailable "All providers failed") id lastErr
    go (p:ps) _lastErr = do
        result <- action p
        case result of
            Success a -> pure $ Right a
            Failure err -> pure $ Left err  -- Non-retryable, fail immediately
            Retry err -> go ps (Just err)   -- Retryable, try next provider
