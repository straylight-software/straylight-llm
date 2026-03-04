{-# LANGUAGE RecordWildCards #-}

-- | WAI runner using io_uring for all network I/O.
--
-- This module provides a high-performance HTTP server that uses io_uring
-- instead of the traditional epoll/kqueue event loop.
--
-- Architecture:
-- - Single-threaded CPS (continuation-passing style) event loop
-- - One io_uring ring per server (or per core with runEvringMultiCore)
-- - No blocking, no MVars in hot path
-- - Buffer pools for zero-allocation steady state
-- - Graceful backpressure when slots exhausted
--
-- Usage:
--
-- @
-- import Evring.Wai (runEvring)
-- import Network.Wai (Application)
--
-- main :: IO ()
-- main = runEvring 8080 myApp
-- @
--
-- For multi-core scaling:
--
-- @
-- import Evring.Wai (runEvringMultiCore)
-- 
-- main :: IO ()
-- main = runEvringMultiCore 8080 myApp  -- Uses SO_REUSEPORT
-- @
--
-- Supports:
-- - Full HTTP/1.1 request parsing (method, path, query, headers)
-- - Request body reading (Content-Length)
-- - WAI Application interface compatible with Servant
-- - HTTP/1.1 Keep-Alive connections
-- - Chunked transfer encoding for streaming responses
-- - WebSocket support via ResponseRaw
-- - Graceful backpressure (no panics on overload)
--
module Evring.Wai
  ( -- * Running WAI applications (single core)
    runEvring
  , runEvringSettings
    -- * Running WAI applications (multi-core)
  , runEvringMultiCore
  , runEvringMultiCoreSettings
    -- * Settings
  , EvringSettings(..)
  , defaultEvringSettings
  ) where

import Network.Wai (Application)

import Evring.Wai.Server qualified as Server
import Evring.Wai.MultiCore qualified as MultiCore

-- | Settings for the evring WAI server.
data EvringSettings = EvringSettings
  { evringPort :: !Int
    -- ^ Port to listen on (default 8080)
  , evringBacklog :: !Int
    -- ^ Listen backlog (default 4096)
  , evringRingSize :: !Int
    -- ^ io_uring ring size (default 4096)
  , evringMaxConnections :: !Int
    -- ^ Maximum concurrent connections per core (default 10000)
  , evringCores :: !(Maybe Int)
    -- ^ Number of cores for multi-core mode (Nothing = all capabilities)
  }

-- | Default settings for port 8080.
defaultEvringSettings :: EvringSettings
defaultEvringSettings = EvringSettings
  { evringPort = 8080
  , evringBacklog = 4096
  , evringRingSize = 4096
  , evringMaxConnections = 10000
  , evringCores = Nothing
  }

-- | Run a WAI application on the given port using io_uring (single core).
runEvring :: Int -> Application -> IO ()
runEvring port app = runEvringSettings (defaultEvringSettings { evringPort = port }) app

-- | Run a WAI application with custom settings using io_uring (single core).
runEvringSettings :: EvringSettings -> Application -> IO ()
runEvringSettings EvringSettings{..} app =
  Server.runServer Server.ServerSettings
    { Server.serverPort = evringPort
    , Server.serverBacklog = evringBacklog
    , Server.serverRingSize = evringRingSize
    , Server.serverMaxConns = evringMaxConnections
    } app

-- | Run a WAI application on the given port using io_uring (multi-core).
-- Uses SO_REUSEPORT for kernel load balancing across cores.
runEvringMultiCore :: Int -> Application -> IO ()
runEvringMultiCore port app = 
  runEvringMultiCoreSettings (defaultEvringSettings { evringPort = port }) app

-- | Run a WAI application with custom settings using io_uring (multi-core).
runEvringMultiCoreSettings :: EvringSettings -> Application -> IO ()
runEvringMultiCoreSettings EvringSettings{..} app =
  MultiCore.runServerMultiCore MultiCore.ServerSettings
    { MultiCore.serverPort = evringPort
    , MultiCore.serverBacklog = evringBacklog
    , MultiCore.serverRingSize = evringRingSize
    , MultiCore.serverMaxConns = evringMaxConnections
    , MultiCore.serverCores = evringCores
    } app
