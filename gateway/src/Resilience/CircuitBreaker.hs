-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                  // straylight-llm // resilience/circuitbreaker
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Night City was like a deranged experiment in social Darwinism,
--      designed by a bored researcher who kept one thumb permanently
--      on the fast-forward button."
--
--                                                              — Neuromancer
--
-- Circuit breaker pattern for provider health management.
--
-- States:
--   Closed  - Normal operation, requests pass through
--   Open    - Provider is unhealthy, requests fail fast
--   HalfOpen - Testing if provider has recovered
--
-- Transitions:
--   Closed -> Open     : When failure count exceeds threshold
--   Open -> HalfOpen   : After cooldown period
--   HalfOpen -> Closed : On successful probe request
--   HalfOpen -> Open   : On failed probe request
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Resilience.CircuitBreaker
    ( -- * Circuit Breaker
      CircuitBreaker
    , CircuitState (..)
    , CircuitBreakerConfig (..)
    , defaultCircuitBreakerConfig
    
      -- * Construction
    , newCircuitBreaker
    
      -- * Operations
    , withCircuitBreaker
    , getCircuitState
    , recordSuccess
    , recordFailure
    , forceOpen
    , forceClose
    
      -- * Stats
    , CircuitStats (..)
    , getCircuitStats
    ) where

import Control.Concurrent.MVar
import Data.IORef
import Data.Text (Text)
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime, NominalDiffTime)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Circuit breaker state
data CircuitState
    = Closed      -- Normal operation
    | Open        -- Failing fast
    | HalfOpen    -- Testing recovery
    deriving (Eq, Show)

-- | Circuit breaker configuration
data CircuitBreakerConfig = CircuitBreakerConfig
    { cbcFailureThreshold :: !Int           -- Failures before opening
    , cbcSuccessThreshold :: !Int           -- Successes to close from half-open
    , cbcCooldownPeriod :: !NominalDiffTime -- How long to stay open before half-open
    , cbcHalfOpenMaxConcurrent :: !Int      -- Max concurrent probes in half-open
    }
    deriving (Eq, Show)

-- | Sensible defaults for LLM providers
defaultCircuitBreakerConfig :: CircuitBreakerConfig
defaultCircuitBreakerConfig = CircuitBreakerConfig
    { cbcFailureThreshold = 5           -- 5 consecutive failures
    , cbcSuccessThreshold = 2           -- 2 successes to fully close
    , cbcCooldownPeriod = 30            -- 30 seconds before retry
    , cbcHalfOpenMaxConcurrent = 1      -- 1 probe at a time
    }

-- | Internal state
data CircuitBreakerState = CircuitBreakerState
    { cbsState :: !CircuitState
    , cbsFailureCount :: !Int
    , cbsSuccessCount :: !Int           -- Only used in HalfOpen
    , cbsLastFailure :: !(Maybe UTCTime)
    , cbsOpenedAt :: !(Maybe UTCTime)
    , cbsHalfOpenProbes :: !Int         -- Current probes in half-open
    }

-- | Circuit breaker for a single provider
data CircuitBreaker = CircuitBreaker
    { cbName :: !Text
    , cbConfig :: !CircuitBreakerConfig
    , cbState :: !(MVar CircuitBreakerState)
    , cbTotalFailures :: !(IORef Int)   -- Lifetime counter
    , cbTotalSuccesses :: !(IORef Int)  -- Lifetime counter
    }

-- | Statistics for observability
data CircuitStats = CircuitStats
    { csName :: !Text
    , csState :: !CircuitState
    , csFailureCount :: !Int
    , csSuccessCount :: !Int
    , csTotalFailures :: !Int
    , csTotalSuccesses :: !Int
    , csLastFailure :: !(Maybe UTCTime)
    , csOpenedAt :: !(Maybe UTCTime)
    }
    deriving (Eq, Show)


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // construction
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a new circuit breaker
newCircuitBreaker :: Text -> CircuitBreakerConfig -> IO CircuitBreaker
newCircuitBreaker name config = do
    stateVar <- newMVar CircuitBreakerState
        { cbsState = Closed
        , cbsFailureCount = 0
        , cbsSuccessCount = 0
        , cbsLastFailure = Nothing
        , cbsOpenedAt = Nothing
        , cbsHalfOpenProbes = 0
        }
    totalFailures <- newIORef 0
    totalSuccesses <- newIORef 0
    pure CircuitBreaker
        { cbName = name
        , cbConfig = config
        , cbState = stateVar
        , cbTotalFailures = totalFailures
        , cbTotalSuccesses = totalSuccesses
        }


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // operations
-- ════════════════════════════════════════════════════════════════════════════

-- | Execute an action through the circuit breaker
--
-- Returns Left error if circuit is open (fail fast).
-- Returns Right (Left providerError) if action failed.
-- Returns Right (Right result) if action succeeded.
--
withCircuitBreaker :: CircuitBreaker -> IO (Either e a) -> IO (Either Text (Either e a))
withCircuitBreaker cb action = do
    -- Check if we can proceed
    canProceed <- checkAndTransition cb
    case canProceed of
        Left err -> pure $ Left err
        Right isProbe -> do
            -- Execute the action
            result <- action
            -- Update state based on result
            case result of
                Left _ -> do
                    recordFailure cb
                    when isProbe $ releaseProbeSlot cb
                Right _ -> do
                    recordSuccess cb
                    when isProbe $ releaseProbeSlot cb
            pure $ Right result
  where
    when True act = act
    when False _ = pure ()

-- | Check current state and possibly transition
-- Returns Left error if open, Right bool (isProbe) if can proceed
checkAndTransition :: CircuitBreaker -> IO (Either Text Bool)
checkAndTransition cb = do
    now <- getCurrentTime
    modifyMVar (cbState cb) $ \st -> do
        case cbsState st of
            Closed -> 
                pure (st, Right False)  -- Not a probe
            
            Open -> do
                -- Check if cooldown has passed
                case cbsOpenedAt st of
                    Nothing -> 
                        -- Shouldn't happen, but handle it
                        pure (st, Left $ "Circuit " <> cbName cb <> " is open")
                    Just openedAt ->
                        if diffUTCTime now openedAt >= cbcCooldownPeriod (cbConfig cb)
                            then do
                                -- Transition to half-open
                                let st' = st { cbsState = HalfOpen
                                             , cbsSuccessCount = 0
                                             , cbsHalfOpenProbes = 1
                                             }
                                pure (st', Right True)  -- Is a probe
                            else
                                pure (st, Left $ "Circuit " <> cbName cb <> " is open (cooldown)")
            
            HalfOpen -> do
                -- Check if we can send another probe
                if cbsHalfOpenProbes st < cbcHalfOpenMaxConcurrent (cbConfig cb)
                    then do
                        let st' = st { cbsHalfOpenProbes = cbsHalfOpenProbes st + 1 }
                        pure (st', Right True)  -- Is a probe
                    else
                        pure (st, Left $ "Circuit " <> cbName cb <> " is half-open (max probes)")

-- | Release a probe slot (called after probe completes)
releaseProbeSlot :: CircuitBreaker -> IO ()
releaseProbeSlot cb =
    modifyMVar_ (cbState cb) $ \st ->
        pure st { cbsHalfOpenProbes = max 0 (cbsHalfOpenProbes st - 1) }

-- | Record a successful request
recordSuccess :: CircuitBreaker -> IO ()
recordSuccess cb = do
    atomicModifyIORef' (cbTotalSuccesses cb) $ \n -> (n + 1, ())
    modifyMVar_ (cbState cb) $ \st ->
        case cbsState st of
            Closed -> 
                -- Reset failure count on success
                pure st { cbsFailureCount = 0 }
            
            HalfOpen -> do
                let newSuccessCount = cbsSuccessCount st + 1
                if newSuccessCount >= cbcSuccessThreshold (cbConfig cb)
                    then
                        -- Enough successes, close the circuit
                        pure st { cbsState = Closed
                                , cbsFailureCount = 0
                                , cbsSuccessCount = 0
                                , cbsOpenedAt = Nothing
                                }
                    else
                        pure st { cbsSuccessCount = newSuccessCount }
            
            Open ->
                -- Shouldn't happen, but don't change state
                pure st

-- | Record a failed request
recordFailure :: CircuitBreaker -> IO ()
recordFailure cb = do
    now <- getCurrentTime
    atomicModifyIORef' (cbTotalFailures cb) $ \n -> (n + 1, ())
    modifyMVar_ (cbState cb) $ \st ->
        case cbsState st of
            Closed -> do
                let newFailureCount = cbsFailureCount st + 1
                if newFailureCount >= cbcFailureThreshold (cbConfig cb)
                    then
                        -- Too many failures, open the circuit
                        pure st { cbsState = Open
                                , cbsFailureCount = newFailureCount
                                , cbsLastFailure = Just now
                                , cbsOpenedAt = Just now
                                }
                    else
                        pure st { cbsFailureCount = newFailureCount
                                , cbsLastFailure = Just now
                                }
            
            HalfOpen ->
                -- Probe failed, back to open
                pure st { cbsState = Open
                        , cbsSuccessCount = 0
                        , cbsLastFailure = Just now
                        , cbsOpenedAt = Just now
                        }
            
            Open ->
                -- Already open, just update timestamp
                pure st { cbsLastFailure = Just now }

-- | Get current circuit state
getCircuitState :: CircuitBreaker -> IO CircuitState
getCircuitState cb = cbsState <$> readMVar (cbState cb)

-- | Force circuit to open state (for manual intervention)
forceOpen :: CircuitBreaker -> IO ()
forceOpen cb = do
    now <- getCurrentTime
    modifyMVar_ (cbState cb) $ \st ->
        pure st { cbsState = Open
                , cbsOpenedAt = Just now
                }

-- | Force circuit to closed state (for manual intervention)
forceClose :: CircuitBreaker -> IO ()
forceClose cb =
    modifyMVar_ (cbState cb) $ \st ->
        pure st { cbsState = Closed
                , cbsFailureCount = 0
                , cbsSuccessCount = 0
                , cbsOpenedAt = Nothing
                }


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // stats
-- ════════════════════════════════════════════════════════════════════════════

-- | Get circuit breaker statistics
getCircuitStats :: CircuitBreaker -> IO CircuitStats
getCircuitStats cb = do
    st <- readMVar (cbState cb)
    totalF <- readIORef (cbTotalFailures cb)
    totalS <- readIORef (cbTotalSuccesses cb)
    pure CircuitStats
        { csName = cbName cb
        , csState = cbsState st
        , csFailureCount = cbsFailureCount st
        , csSuccessCount = cbsSuccessCount st
        , csTotalFailures = totalF
        , csTotalSuccesses = totalS
        , csLastFailure = cbsLastFailure st
        , csOpenedAt = cbsOpenedAt st
        }
