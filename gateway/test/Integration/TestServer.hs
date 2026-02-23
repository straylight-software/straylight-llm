-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                    // straylight-llm // integration // server
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The sky above the port was the color of television,
--      tuned to a dead channel."
--
--                                                              — Neuromancer
--
-- Test server infrastructure for integration testing.
-- Provides test configuration and Warp test utilities for testing the full
-- request/response cycle without external provider dependencies.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Integration.TestServer
    ( -- * Test Utilities
      withTestApp
    , testApp
    , TestEnv (..)

      -- * Test Config
    , testConfig
    , disabledConfig
    ) where

import Network.HTTP.Client qualified as HC
import Network.HTTP.Client.TLS qualified as HCT
import Network.Wai (Application)
import Network.Wai.Handler.Warp qualified as Warp
import Servant (serve)

import Api (api)
import Config
import Handlers (server)
import Router (Router, makeRouter)


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // test config
-- ════════════════════════════════════════════════════════════════════════════

-- | Disabled provider config
disabledProvider :: ProviderConfig
disabledProvider = ProviderConfig
    { pcEnabled = False
    , pcBaseUrl = ""
    , pcApiKeyPath = Nothing
    , pcApiKey = Nothing
    , pcVertexConfig = Nothing
    }

-- | Test configuration with all external providers disabled
-- This allows testing health endpoint and error paths
disabledConfig :: Config
disabledConfig = Config
    { cfgPort = 0  -- Unused, Warp.testWithApplication picks port
    , cfgHost = "127.0.0.1"
    , cfgVenice = disabledProvider
    , cfgVertex = disabledProvider
    , cfgBaseten = disabledProvider
    , cfgOpenRouter = disabledProvider
    , cfgAnthropic = disabledProvider
    , cfgLogLevel = "warn"
    , cfgRequestTimeout = 5
    , cfgMaxRetries = 1
    }

-- | Test configuration with OpenRouter pointing to non-existent server
-- This allows testing provider error paths (connection refused)
testConfig :: Config
testConfig = disabledConfig
    { cfgOpenRouter = ProviderConfig
        { pcEnabled = True
        , pcBaseUrl = "http://127.0.0.1:59999"  -- Non-existent port
        , pcApiKeyPath = Nothing
        , pcApiKey = Just "test-key-12345"
        , pcVertexConfig = Nothing
        }
    }


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // test server
-- ════════════════════════════════════════════════════════════════════════════

-- | Test environment
data TestEnv = TestEnv
    { teRouter :: Router
    , teManager :: HC.Manager
    , tePort :: Warp.Port
    }

-- | Create the Wai Application for testing
testApp :: Config -> IO Application
testApp config = do
    router <- makeRouter config
    pure $ serve api (server router)

-- | Run an action with a test server
-- Uses Warp.testWithApplication for proper port allocation and cleanup
withTestApp :: Config -> (TestEnv -> IO a) -> IO a
withTestApp config action = do
    router <- makeRouter config
    manager <- HC.newManager HCT.tlsManagerSettings
    let app = serve api (server router)
    Warp.testWithApplication (pure app) $ \port -> do
        action TestEnv
            { teRouter = router
            , teManager = manager
            , tePort = port
            }
