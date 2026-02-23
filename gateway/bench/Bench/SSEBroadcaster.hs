-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                               // straylight-llm // bench/SSEBroadcaster.hs
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- SSE event broadcaster performance benchmarks.
--
-- Tests:
--   - Event broadcast latency
--   - Subscriber scaling (1, 10, 100, 1000 subscribers)
--   - Event encoding overhead
--   - Concurrent broadcast patterns
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE BangPatterns #-}

module Bench.SSEBroadcaster (benchmarks) where

import Control.Concurrent.Async (replicateConcurrently_)
import Control.DeepSeq (force)
import Control.Monad (replicateM_)
import Criterion.Main
    ( Benchmark
    , bench
    , bgroup
    , nfIO
    , nf
    , whnfIO
    )
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import System.IO.Unsafe (unsafePerformIO)

import Streaming.Events
    ( EventBroadcaster
    , SSEEvent
        ( SSERequestStarted
        , SSERequestCompleted
        , SSEProofGenerated
        , SSEProviderStatus
        , SSEKeepalive
        )
    , RequestStartedData
        ( RequestStartedData
        , rsdRequestId
        , rsdModel
        , rsdTimestamp
        )
    , RequestCompletedData
        ( RequestCompletedData
        , rcdRequestId
        , rcdModel
        , rcdProvider
        , rcdSuccess
        , rcdLatencyMs
        , rcdError
        , rcdTimestamp
        )
    , ProofGeneratedData
        ( ProofGeneratedData
        , pgdRequestId
        , pgdCoeffects
        , pgdSigned
        , pgdTimestamp
        )
    , ProviderStatusData
        ( ProviderStatusData
        , psdProvider
        , psdState
        , psdFailures
        , psdThreshold
        , psdLastFailure
        , psdTimestamp
        )
    , CircuitState (CircuitOpen)
    , newEventBroadcaster
    , subscribe
    , broadcast
    , encodeSSEEvent
    )


-- | All SSE broadcaster benchmarks
benchmarks :: Benchmark
benchmarks = bgroup "SSEBroadcaster"
    [ encodingBenchmarks
    , broadcastBenchmarks
    , subscriberScalingBenchmarks
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                    // global refs for env
-- ════════════════════════════════════════════════════════════════════════════

-- | Global broadcaster ref (avoids NFData requirement)
{-# NOINLINE broadcasterRef #-}
broadcasterRef :: IORef (Maybe EventBroadcaster)
broadcasterRef = unsafePerformIO $ newIORef Nothing



-- | Get or create broadcaster
getBroadcaster :: IO EventBroadcaster
getBroadcaster = do
    mbc <- readIORef broadcasterRef
    case mbc of
        Just bc -> pure bc
        Nothing -> do
            bc <- newEventBroadcaster
            writeIORef broadcasterRef (Just bc)
            pure bc




-- ════════════════════════════════════════════════════════════════════════════
--                                                         // event encoding
-- ════════════════════════════════════════════════════════════════════════════

-- | Sample events for benchmarking
sampleRequestStarted :: SSEEvent
sampleRequestStarted = SSERequestStarted RequestStartedData
    { rsdRequestId = "req_abc123def456"
    , rsdModel = "llama-3.3-70b"
    , rsdTimestamp = "2026-02-23T19:00:00Z"
    }

sampleRequestCompleted :: SSEEvent
sampleRequestCompleted = SSERequestCompleted RequestCompletedData
    { rcdRequestId = "req_abc123def456"
    , rcdModel = "llama-3.3-70b"
    , rcdProvider = Just "venice"
    , rcdSuccess = True
    , rcdLatencyMs = 234.56
    , rcdError = Nothing
    , rcdTimestamp = "2026-02-23T19:00:01Z"
    }

sampleProofGenerated :: SSEEvent
sampleProofGenerated = SSEProofGenerated ProofGeneratedData
    { pgdRequestId = "req_abc123def456"
    , pgdCoeffects = ["network", "auth:venice", "auth:anthropic"]
    , pgdSigned = True
    , pgdTimestamp = "2026-02-23T19:00:01Z"
    }

sampleProviderStatus :: SSEEvent
sampleProviderStatus = SSEProviderStatus ProviderStatusData
    { psdProvider = "vertex"
    , psdState = CircuitOpen
    , psdFailures = 5
    , psdThreshold = 5
    , psdLastFailure = Just "2026-02-23T18:59:55Z"
    , psdTimestamp = "2026-02-23T19:00:00Z"
    }

encodingBenchmarks :: Benchmark
encodingBenchmarks = bgroup "Encoding"
    [ bench "keepalive" $ nf encodeSSEEvent SSEKeepalive
    , bench "request.started" $ nf encodeSSEEvent sampleRequestStarted
    , bench "request.completed" $ nf encodeSSEEvent sampleRequestCompleted
    , bench "proof.generated" $ nf encodeSSEEvent sampleProofGenerated
    , bench "provider.status" $ nf encodeSSEEvent sampleProviderStatus
    , bench "encode/100-events" $ nfIO $ do
        let events = cycle 
                [ sampleRequestStarted
                , sampleRequestCompleted
                , sampleProofGenerated
                , sampleProviderStatus
                ]
        pure $! force $ map encodeSSEEvent (take 100 events)
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                     // broadcast latency
-- ════════════════════════════════════════════════════════════════════════════

-- | Global ref for broadcaster with one subscriber
{-# NOINLINE broadcasterWithOneSubRef #-}
broadcasterWithOneSubRef :: IORef (Maybe EventBroadcaster)
broadcasterWithOneSubRef = unsafePerformIO $ newIORef Nothing

-- | Get broadcaster with one subscriber (cleanup is intentionally leaked for benchmarking)
getBroadcasterWithOneSub :: IO EventBroadcaster
getBroadcasterWithOneSub = do
    mbc <- readIORef broadcasterWithOneSubRef
    case mbc of
        Just bc -> pure bc
        Nothing -> do
            bc <- newEventBroadcaster
            -- Subscribe but intentionally don't cleanup during benchmark
            _ <- subscribe bc
            writeIORef broadcasterWithOneSubRef (Just bc)
            pure bc

broadcastBenchmarks :: Benchmark
broadcastBenchmarks = bgroup "Broadcast"
    [ bgroup "noSubscribers"
        [ bench "single" $ whnfIO $ do
            bc <- getBroadcaster
            broadcast bc sampleRequestStarted
        , bench "100-events" $ nfIO $ do
            bc <- getBroadcaster
            replicateM_ 100 $ broadcast bc sampleRequestCompleted
        , bench "1000-events" $ nfIO $ do
            bc <- getBroadcaster
            replicateM_ 1000 $ broadcast bc SSEKeepalive
        ]
    , bgroup "oneSubscriber"
        [ bench "single" $ whnfIO $ do
            bc <- getBroadcasterWithOneSub
            broadcast bc sampleRequestStarted
        , bench "100-events" $ nfIO $ do
            bc <- getBroadcasterWithOneSub
            replicateM_ 100 $ broadcast bc sampleRequestCompleted
        ]
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                    // subscriber scaling
-- ════════════════════════════════════════════════════════════════════════════

-- | Global refs for subscriber scaling benchmarks
{-# NOINLINE sub1BroadcasterRef #-}
sub1BroadcasterRef :: IORef (Maybe EventBroadcaster)
sub1BroadcasterRef = unsafePerformIO $ newIORef Nothing

{-# NOINLINE sub10BroadcasterRef #-}
sub10BroadcasterRef :: IORef (Maybe EventBroadcaster)
sub10BroadcasterRef = unsafePerformIO $ newIORef Nothing

{-# NOINLINE sub100BroadcasterRef #-}
sub100BroadcasterRef :: IORef (Maybe EventBroadcaster)
sub100BroadcasterRef = unsafePerformIO $ newIORef Nothing

{-# NOINLINE sub1000BroadcasterRef #-}
sub1000BroadcasterRef :: IORef (Maybe EventBroadcaster)
sub1000BroadcasterRef = unsafePerformIO $ newIORef Nothing

-- | Setup broadcaster with N subscribers (cleanup leaked for benchmarking)
setupBroadcasterWithNSubs :: IORef (Maybe EventBroadcaster) -> Int -> IO EventBroadcaster
setupBroadcasterWithNSubs ref n = do
    mbc <- readIORef ref
    case mbc of
        Just bc -> pure bc
        Nothing -> do
            bc <- newEventBroadcaster
            replicateM_ n $ subscribe bc  -- Leak cleanups intentionally
            writeIORef ref (Just bc)
            pure bc

subscriberScalingBenchmarks :: Benchmark
subscriberScalingBenchmarks = bgroup "SubscriberScaling"
    [ bench "1-subscriber/broadcast" $ whnfIO $ do
        bc <- setupBroadcasterWithNSubs sub1BroadcasterRef 1
        broadcast bc sampleRequestCompleted
    , bench "10-subscribers/broadcast" $ whnfIO $ do
        bc <- setupBroadcasterWithNSubs sub10BroadcasterRef 10
        broadcast bc sampleRequestCompleted
    , bench "100-subscribers/broadcast" $ whnfIO $ do
        bc <- setupBroadcasterWithNSubs sub100BroadcasterRef 100
        broadcast bc sampleRequestCompleted
    , bench "1000-subscribers/broadcast" $ whnfIO $ do
        bc <- setupBroadcasterWithNSubs sub1000BroadcasterRef 1000
        broadcast bc sampleRequestCompleted
    , bgroup "subscribe"
        [ bench "subscribe/single" $ whnfIO $ do
            bc <- getBroadcaster
            (_, _, cleanup) <- subscribe bc
            cleanup
        , bench "subscribe/10-concurrent" $ nfIO $ do
            bc <- getBroadcaster
            replicateConcurrently_ 10 $ do
                (_, _, cleanup) <- subscribe bc
                cleanup
        ]
    , bgroup "fullCycle"
        [ bench "broadcast+receive/10-subs" $ whnfIO $ do
            bc <- setupBroadcasterWithNSubs sub10BroadcasterRef 10
            broadcast bc sampleRequestStarted
        ]
    ]
