{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                       // straylight // health
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   Health check endpoint handler.
   cf. /health and /ready endpoints
-}
module Straylight.Endpoints.Health
  ( handleHealth
  , handleReady
  ) where

import Data.Aeson (encode)
import Data.IORef
import qualified Data.Text as T
import Network.HTTP.Types
import Network.Wai

import Straylight.Config
import Straylight.Router
import Straylight.Types


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // health // handlers
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Handle /health endpoint
handleHealth :: RouterState -> IO Response
handleHealth RouterState{..} = do
  cgpHealthy <- readIORef rsCgpHealthy
  orHealthy  <- readIORef rsOrHealthy

  let cgpConfigured = cgpEnabled rsConfig
      orConfigured  = openRouterEnabled rsConfig

      status
        | cgpHealthy || orHealthy = HealthOk
        | cgpConfigured || orConfigured = HealthDegraded
        | otherwise = HealthUnhealthy

      response = HealthResponse
        { hrStatus = status
        , hrCgp = BackendHealth
            { bhConfigured = cgpConfigured
            , bhHealthy    = cgpHealthy
            , bhApiBase    = if cgpConfigured
                then Just $ cgpApiBase $ cfgCgp rsConfig
                else Nothing
            }
        , hrOpenRouter = BackendHealth
            { bhConfigured = orConfigured
            , bhHealthy    = orHealthy
            , bhApiBase    = if orConfigured
                then Just $ orApiBase $ cfgOpenRouter rsConfig
                else Nothing
            }
        }

      httpStatus = case status of
        HealthOk        -> status200
        HealthDegraded  -> status200  -- n.b. still 200 for load balancers
        HealthUnhealthy -> status503

  pure $ responseLBS httpStatus jsonHeaders (encode response)


-- | Handle /ready endpoint (for k8s readiness probes)
handleReady :: RouterState -> IO Response
handleReady RouterState{..} = do
  cgpHealthy <- readIORef rsCgpHealthy
  orHealthy  <- readIORef rsOrHealthy

  if cgpHealthy || orHealthy
    then pure $ responseLBS status200 jsonHeaders "{\"ready\":true}"
    else pure $ responseLBS status503 jsonHeaders "{\"ready\":false}"


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // helpers
   ════════════════════════════════════════════════════════════════════════════════ -}

jsonHeaders :: [Header]
jsonHeaders = [("Content-Type", "application/json")]
