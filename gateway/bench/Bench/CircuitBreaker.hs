-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                               // straylight-llm // bench/CircuitBreaker.hs
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- Circuit breaker performance benchmarks.
--
-- Tests:
--   - State check latency (critical path)
--   - State transition overhead
--   - Concurrent access patterns
--   - Stats collection overhead
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE BangPatterns #-}

module Bench.CircuitBreaker (benchmarks) where

import Control.Concurrent.Async (replicateConcurrently_)
import Control.Monad (replicateM_)
import Criterion.Main
    ( Benchmark
    , bench
    , bgroup
    , nfIO
    , whnfIO
    )
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import System.IO.Unsafe (unsafePerformIO)

import Resilience.CircuitBreaker
    ( CircuitBreaker
    , defaultCircuitBreakerConfig
    , newCircuitBreaker
    , withCircuitBreaker
    , getCircuitState
    , getCircuitStats
    , recordSuccess
    , recordFailure
    , forceOpen
    , forceClose
    )


-- | All circuit breaker benchmarks
benchmarks :: Benchmark
benchmarks = bgroup "CircuitBreaker"
    [ stateCheckBenchmarks
    , transitionBenchmarks
    , withCircuitBreakerBenchmarks
    , concurrentBenchmarks
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // state checks
-- ════════════════════════════════════════════════════════════════════════════

-- | Global refs for benchmarking (avoids NFData requirement)
{-# NOINLINE closedCircuitRef #-}
closedCircuitRef :: IORef (Maybe CircuitBreaker)
closedCircuitRef = unsafePerformIO $ newIORef Nothing

{-# NOINLINE openCircuitRef #-}
openCircuitRef :: IORef (Maybe CircuitBreaker)
openCircuitRef = unsafePerformIO $ newIORef Nothing

-- | Initialize circuits once
initCircuits :: IO ()
initCircuits = do
    closedCB <- newCircuitBreaker "bench-closed" defaultCircuitBreakerConfig
    writeIORef closedCircuitRef (Just closedCB)
    
    openCB <- newCircuitBreaker "bench-open" defaultCircuitBreakerConfig
    forceOpen openCB
    writeIORef openCircuitRef (Just openCB)

-- | Get the closed circuit (initializes if needed)
getClosedCircuit :: IO CircuitBreaker
getClosedCircuit = do
    mcb <- readIORef closedCircuitRef
    case mcb of
        Just cb -> pure cb
        Nothing -> do
            initCircuits
            Just cb <- readIORef closedCircuitRef
            pure cb

-- | Get the open circuit (initializes if needed)
getOpenCircuit :: IO CircuitBreaker
getOpenCircuit = do
    mcb <- readIORef openCircuitRef
    case mcb of
        Just cb -> pure cb
        Nothing -> do
            initCircuits
            Just cb <- readIORef openCircuitRef
            pure cb

stateCheckBenchmarks :: Benchmark
stateCheckBenchmarks = bgroup "StateCheck"
    [ bench "getState/closed" $ whnfIO $ do
        cb <- getClosedCircuit
        getCircuitState cb
    , bench "getState/open" $ whnfIO $ do
        cb <- getOpenCircuit
        getCircuitState cb
    , bench "getStats" $ whnfIO $ do
        cb <- getClosedCircuit
        getCircuitStats cb
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // state transitions
-- ════════════════════════════════════════════════════════════════════════════

transitionBenchmarks :: Benchmark
transitionBenchmarks = bgroup "Transitions"
    [ bench "recordSuccess" $ whnfIO $ do
        cb <- newCircuitBreaker "bench" defaultCircuitBreakerConfig
        recordSuccess cb
    , bench "recordFailure" $ whnfIO $ do
        cb <- newCircuitBreaker "bench" defaultCircuitBreakerConfig
        recordFailure cb
    , bench "recordFailure/5x-to-open" $ whnfIO $ do
        cb <- newCircuitBreaker "bench" defaultCircuitBreakerConfig
        -- Default threshold is 5 failures
        replicateM_ 5 (recordFailure cb)
    , bench "forceOpen" $ whnfIO $ do
        cb <- newCircuitBreaker "bench" defaultCircuitBreakerConfig
        forceOpen cb
    , bench "forceClose" $ whnfIO $ do
        cb <- newCircuitBreaker "bench" defaultCircuitBreakerConfig
        forceOpen cb
        forceClose cb
    , bench "closed->open->closed" $ whnfIO $ do
        cb <- newCircuitBreaker "bench" defaultCircuitBreakerConfig
        forceOpen cb
        forceClose cb
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                    // withCircuitBreaker
-- ════════════════════════════════════════════════════════════════════════════

withCircuitBreakerBenchmarks :: Benchmark
withCircuitBreakerBenchmarks = bgroup "WithCircuitBreaker"
    [ bench "closed/success" $ whnfIO $ do
        cb <- getClosedCircuit
        withCircuitBreaker cb (pure (Right ()))
    , bench "closed/failure" $ whnfIO $ do
        cb <- getClosedCircuit
        withCircuitBreaker cb (pure (Left "error" :: Either String ()))
    , bench "open/fast-fail" $ whnfIO $ do
        cb <- getOpenCircuit
        withCircuitBreaker cb (pure (Right ()))
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                         // concurrent access
-- ════════════════════════════════════════════════════════════════════════════

concurrentBenchmarks :: Benchmark
concurrentBenchmarks = bgroup "Concurrent"
    [ bench "stateCheck/10-concurrent" $ nfIO $ do
        cb <- getClosedCircuit
        replicateConcurrently_ 10 (getCircuitState cb)
    , bench "stateCheck/100-concurrent" $ nfIO $ do
        cb <- getClosedCircuit
        replicateConcurrently_ 100 (getCircuitState cb)
    , bench "stateCheck/1000-concurrent" $ nfIO $ do
        cb <- getClosedCircuit
        replicateConcurrently_ 1000 (getCircuitState cb)
    , bench "recordSuccess/10-concurrent" $ nfIO $ do
        cb <- getClosedCircuit
        replicateConcurrently_ 10 (recordSuccess cb)
    , bench "recordSuccess/100-concurrent" $ nfIO $ do
        cb <- getClosedCircuit
        replicateConcurrently_ 100 (recordSuccess cb)
    , bench "withCircuitBreaker/10-concurrent" $ nfIO $ do
        cb <- getClosedCircuit
        replicateConcurrently_ 10 $ withCircuitBreaker cb (pure (Right ()))
    , bench "withCircuitBreaker/100-concurrent" $ nfIO $ do
        cb <- getClosedCircuit
        replicateConcurrently_ 100 $ withCircuitBreaker cb (pure (Right ()))
    , bench "fastFail/100-concurrent" $ nfIO $ do
        cb <- getOpenCircuit
        replicateConcurrently_ 100 $ withCircuitBreaker cb (pure (Right ()))
    , bench "fastFail/1000-concurrent" $ nfIO $ do
        cb <- getOpenCircuit
        replicateConcurrently_ 1000 $ withCircuitBreaker cb (pure (Right ()))
    ]