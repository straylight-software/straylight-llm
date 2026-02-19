{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                       // straylight // router
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   "Case sensed the shape of the lock, its most deeply-buried
    cylinder. He watched her revolve in the semisolid jelly
    of her seat, her hands dancing across the deck."

                                                               — Neuromancer

   CGP-first routing logic with OpenRouter fallback.
   n.b. corresponds to Lean4 Straylight.Router proofs.
-}
module Straylight.Router
  ( -- // routing // types
    RoutingDecision (..)
  , RouterState (..)
    -- // routing // functions
  , newRouterState
  , decideRoute
  , routeRequest
  , routeStreamingRequest
  , updateHealth
  ) where

import Control.Concurrent.MVar
import Data.IORef
import Data.Text (Text)

import Straylight.Config
import Straylight.Providers.Base
import Straylight.Providers.Cgp
import Straylight.Providers.OpenRouter
import Straylight.Types


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // routing // decision
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | The result of a routing decision.
--   cf. Lean4 Straylight.Router.RoutingDecision
data RoutingDecision
  = RouteToCgp
  | RouteToOpenRouter
  | NoBackendAvailable
  deriving stock (Eq, Show)


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // router // state
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Router state with providers and health status
data RouterState = RouterState
  { rsConfig      :: !Config
  , rsCgp         :: !(Maybe CgpProvider)
  , rsOpenRouter  :: !(Maybe OpenRouterProvider)
  , rsCgpHealthy  :: !(IORef Bool)
  , rsOrHealthy   :: !(IORef Bool)
  }


-- | Create a new router state from configuration
newRouterState :: Config -> IO RouterState
newRouterState cfg = do
  cgpProvider <- if cgpEnabled cfg
    then Just <$> newCgpProvider (cfgCgp cfg)
    else pure Nothing

  orProvider <- if openRouterEnabled cfg
    then Just <$> newOpenRouterProvider (cfgOpenRouter cfg)
    else pure Nothing

  cgpHealthRef <- newIORef False
  orHealthRef  <- newIORef (openRouterEnabled cfg)

  pure RouterState
    { rsConfig     = cfg
    , rsCgp        = cgpProvider
    , rsOpenRouter = orProvider
    , rsCgpHealthy = cgpHealthRef
    , rsOrHealthy  = orHealthRef
    }


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // routing // logic
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Determine where to route a request.
--   cf. Lean4 theorem cgpFirstWhenHealthy
decideRoute :: RouterState -> IO RoutingDecision
decideRoute RouterState{..} = do
  cgpHealthy <- readIORef rsCgpHealthy
  orHealthy  <- readIORef rsOrHealthy

  pure $ case (rsCgp, cgpHealthy, rsOpenRouter, orHealthy) of
    (Just _, True, _, _)       -> RouteToCgp
    (_, _, Just _, True)       -> RouteToOpenRouter
    _                          -> NoBackendAvailable


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // request // routing
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Route a chat completion request with fallback.
--   n.b. implements cgp-first with automatic fallback on 5xx
routeRequest
  :: RouterState
  -> Text           -- ^ model
  -> [ChatMessage]  -- ^ messages
  -> Maybe Double   -- ^ temperature
  -> Maybe Double   -- ^ top_p
  -> Maybe Int      -- ^ max_tokens
  -> IO (ProviderResult ChatResponse)
routeRequest rs@RouterState{..} model msgs temp topP maxTokens = do
  decision <- decideRoute rs

  case decision of
    NoBackendAvailable ->
      pure $ ProviderFailure $ mkProviderError "No backend available" 503

    RouteToCgp -> do
      result <- case rsCgp of
        Just cgp -> cgpChatCompletion cgp model msgs temp topP maxTokens
        Nothing  -> pure $ ProviderFailure $ mkProviderError "CGP not configured" 503

      -- If CGP fails with retryable error, try OpenRouter
      case result of
        ProviderSuccess r -> pure $ ProviderSuccess r
        ProviderFailure e | peRetryable e -> do
          -- Mark CGP as unhealthy
          writeIORef rsCgpHealthy False
          -- Try OpenRouter fallback
          case rsOpenRouter of
            Just or' -> orChatCompletion or' model msgs temp topP maxTokens
            Nothing  -> pure $ ProviderFailure e
        ProviderFailure e -> pure $ ProviderFailure e

    RouteToOpenRouter -> do
      case rsOpenRouter of
        Just or' -> orChatCompletion or' model msgs temp topP maxTokens
        Nothing  -> pure $ ProviderFailure $ mkProviderError "OpenRouter not configured" 503


-- | Route a streaming chat completion request with fallback
routeStreamingRequest
  :: RouterState
  -> Text           -- ^ model
  -> [ChatMessage]  -- ^ messages
  -> Maybe Double   -- ^ temperature
  -> Maybe Double   -- ^ top_p
  -> Maybe Int      -- ^ max_tokens
  -> (StreamChunk -> IO ())  -- ^ chunk handler
  -> IO (ProviderResult ())
routeStreamingRequest rs@RouterState{..} model msgs temp topP maxTokens onChunk = do
  decision <- decideRoute rs

  case decision of
    NoBackendAvailable ->
      pure $ ProviderFailure $ mkProviderError "No backend available" 503

    RouteToCgp -> do
      result <- case rsCgp of
        Just cgp -> cgpChatCompletionStream cgp model msgs temp topP maxTokens onChunk
        Nothing  -> pure $ ProviderFailure $ mkProviderError "CGP not configured" 503

      case result of
        ProviderSuccess () -> pure $ ProviderSuccess ()
        ProviderFailure e | peRetryable e -> do
          writeIORef rsCgpHealthy False
          case rsOpenRouter of
            Just or' -> orChatCompletionStream or' model msgs temp topP maxTokens onChunk
            Nothing  -> pure $ ProviderFailure e
        ProviderFailure e -> pure $ ProviderFailure e

    RouteToOpenRouter -> do
      case rsOpenRouter of
        Just or' -> orChatCompletionStream or' model msgs temp topP maxTokens onChunk
        Nothing  -> pure $ ProviderFailure $ mkProviderError "OpenRouter not configured" 503


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // health // updates
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Update health status for all providers
updateHealth :: RouterState -> IO ()
updateHealth RouterState{..} = do
  -- Check CGP health
  case rsCgp of
    Just cgp -> do
      healthy <- cgpHealth cgp
      writeIORef rsCgpHealthy healthy
    Nothing -> pure ()

  -- Check OpenRouter health (just API key presence)
  case rsOpenRouter of
    Just or' -> do
      healthy <- orHealth or'
      writeIORef rsOrHealthy healthy
    Nothing -> pure ()
