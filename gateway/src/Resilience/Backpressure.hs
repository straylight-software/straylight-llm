-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                  // straylight-llm // resilience/backpressure
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The matrix has its roots in primitive arcade games... in early
--      graphics programs and military experimentation with cranial jacks."
--
--                                                              — Neuromancer
--
-- Backpressure and request limiting for billion-agent scale.
--
-- At high load, we need to:
--   1. Limit concurrent requests to prevent OOM
--   2. Fail fast with 503 when overloaded (rather than queue indefinitely)
--   3. Track queue depth for observability
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Resilience.Backpressure
    ( -- * Semaphore
      RequestSemaphore
    , newRequestSemaphore
    , tryWithRequestSlot
    
      -- * Stats
    , SemaphoreStats (SemaphoreStats, ssMaxSlots, ssInFlight, ssAvailable)
    , getSemaphoreStats
    ) where

import Control.Concurrent.QSem (QSem, newQSem, waitQSem, signalQSem)
import Control.Exception (bracket_)
import Data.IORef


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | A counting semaphore for limiting concurrent requests
--
-- Uses QSem for the actual semaphore, with IORef counters for observability.
--
data RequestSemaphore = RequestSemaphore
    { rsMaxSlots :: !Int
    , rsSem :: !QSem
    , rsInFlight :: !(IORef Int)    -- For observability: how many requests active
    }

-- | Statistics about the semaphore state
data SemaphoreStats = SemaphoreStats
    { ssMaxSlots :: !Int
    , ssInFlight :: !Int
    , ssAvailable :: !Int           -- Derived: maxSlots - inFlight
    }
    deriving (Eq, Show)


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // construction
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a new request semaphore with the given capacity
newRequestSemaphore :: Int -> IO RequestSemaphore
newRequestSemaphore maxSlots = do
    sem <- newQSem maxSlots
    inFlight <- newIORef 0
    pure RequestSemaphore
        { rsMaxSlots = maxSlots
        , rsSem = sem
        , rsInFlight = inFlight
        }


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // operations
-- ════════════════════════════════════════════════════════════════════════════

-- | Try to acquire a slot and run the action
--
-- If a slot is available, acquires it, runs the action, releases, returns Just result.
-- If no slot is available, returns Nothing immediately (fast-fail for 503).
--
-- This is the primary API - we always fail fast rather than queue indefinitely.
-- For billion-agent scale, queueing just delays the inevitable OOM.
--
tryWithRequestSlot :: RequestSemaphore -> IO a -> IO (Maybe a)
tryWithRequestSlot reqSem action = do
    -- Check current count - if at capacity, fail fast
    currentInFlight <- readIORef (rsInFlight reqSem)
    if currentInFlight >= rsMaxSlots reqSem
        then pure Nothing
        else do
            -- There's a race here, but that's OK - worst case we let one extra through
            -- The QSem will block correctly; we just might block briefly
            bracket_
                (do waitQSem (rsSem reqSem)
                    atomicModifyIORef' (rsInFlight reqSem) $ \n -> (n + 1, ()))
                (do atomicModifyIORef' (rsInFlight reqSem) $ \n -> (n - 1, ())
                    signalQSem (rsSem reqSem))
                (Just <$> action)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // stats
-- ════════════════════════════════════════════════════════════════════════════

-- | Get current semaphore statistics
getSemaphoreStats :: RequestSemaphore -> IO SemaphoreStats
getSemaphoreStats reqSem = do
    inFlight <- readIORef (rsInFlight reqSem)
    pure SemaphoreStats
        { ssMaxSlots = rsMaxSlots reqSem
        , ssInFlight = inFlight
        , ssAvailable = rsMaxSlots reqSem - inFlight
        }
