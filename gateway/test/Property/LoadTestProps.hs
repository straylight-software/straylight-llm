-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                             // straylight-llm // property // load test props
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Night City was like a deranged experiment in social Darwinism,
--      designed by a bored researcher who kept one thumb permanently on
--      the fast-forward button."
--
--                                                              — Neuromancer
--
-- Property-based stress tests for concurrent metrics recording.
-- Tests the REAL MetricsStore under high load and concurrency.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}

module Property.LoadTestProps
    ( tests
    ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (replicateConcurrently, mapConcurrently)
import Control.Monad (forM_, replicateM)
import Data.IORef (newIORef, readIORef, atomicModifyIORef')
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import Data.Word (Word64)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.Hedgehog

import Resilience.Metrics
    ( MetricsStore
    , Metrics (..)
    , ProviderMetrics (..)
    , LatencyBuckets (..)
    , newMetricsStore
    , recordRequest
    , recordRequestComplete
    , recordProviderRequest
    , recordProviderError
    , recordLatency
    , getMetrics
    )
import Provider.Types (ProviderError (..), ProviderName (..))


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // property tests
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "Load Tests"
    [ testGroup "Concurrency"
        [ testProperty "concurrent_increments_atomic" prop_concurrentIncrementsAtomic
        , testProperty "concurrent_workers_independent" prop_concurrentWorkersIndependent
        , testProperty "high_concurrency_no_data_loss" prop_highConcurrencyNoDataLoss
        ]
    , testGroup "Throughput"
        [ testProperty "metrics_scale_linearly" prop_metricsScaleLinearly
        , testProperty "latency_recording_accurate" prop_latencyRecordingAccurate
        ]
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                               // concurrency properties
-- ════════════════════════════════════════════════════════════════════════════

-- | Concurrent increments should result in correct total (atomic ops)
prop_concurrentIncrementsAtomic :: Property
prop_concurrentIncrementsAtomic = withTests 50 $ property $ do
    numThreads <- forAll $ Gen.int (Range.linear 2 20)
    incrementsPerThread <- forAll $ Gen.int (Range.linear 100 1000)
    
    store <- evalIO newMetricsStore
    
    -- Spawn concurrent threads that all record requests
    evalIO $ replicateConcurrently numThreads $ do
        forM_ [1..incrementsPerThread] $ \_ -> do
            startTime <- recordRequest store
            recordRequestComplete store startTime
    
    -- Check final count
    finalMetrics <- evalIO $ getMetrics store
    let expectedTotal = fromIntegral $ numThreads * incrementsPerThread
    mRequestsTotal finalMetrics === expectedTotal

-- | Each worker writes to its own provider - verify independence
prop_concurrentWorkersIndependent :: Property
prop_concurrentWorkersIndependent = withTests 30 $ property $ do
    -- Use 5 providers (enum doesn't have arbitrary count)
    let providers = [Triton, Venice, Anthropic, OpenRouter, Together]
        numWorkers = length providers
    requestsEach <- forAll $ Gen.int (Range.linear 50 200)
    
    store <- evalIO newMetricsStore
    
    -- Each worker records to a different provider
    evalIO $ mapConcurrently (\provider -> do
        forM_ [1..requestsEach] $ \_ -> do
            startTime <- recordRequest store
            recordProviderRequest store provider
            recordLatency store provider 0.001
            recordRequestComplete store startTime
        ) providers
    
    metrics <- evalIO $ getMetrics store
    
    -- Total should be sum of all workers
    mRequestsTotal metrics === fromIntegral (numWorkers * requestsEach)
    
    -- Each provider should have correct count
    let providerCounts = Map.map pmRequestsTotal (mProviders metrics)
    forM_ providers $ \provider -> do
        case Map.lookup provider providerCounts of
            Just count -> count === fromIntegral requestsEach
            Nothing -> failure

-- | High concurrency blast should not lose any data
prop_highConcurrencyNoDataLoss :: Property
prop_highConcurrencyNoDataLoss = withTests 10 $ property $ do
    -- Stress test: 50 threads, 500 requests each = 25,000 total
    let numThreads = 50
        requestsPerThread = 500
        expectedTotal = fromIntegral $ numThreads * requestsPerThread
        providers = [Triton, Venice, Anthropic, OpenRouter, Together]
    
    store <- evalIO newMetricsStore
    
    evalIO $ replicateConcurrently numThreads $ do
        forM_ [1..requestsPerThread] $ \i -> do
            let provider = providers !! (i `mod` length providers)
            startTime <- recordRequest store
            recordProviderRequest store provider
            recordLatency store provider 0.0001
            recordRequestComplete store startTime
    
    finalMetrics <- evalIO $ getMetrics store
    
    -- Must not lose ANY requests
    mRequestsTotal finalMetrics === expectedTotal


-- ════════════════════════════════════════════════════════════════════════════
--                                                 // throughput properties
-- ════════════════════════════════════════════════════════════════════════════

-- | Metrics should scale linearly (2x requests = 2x count)
prop_metricsScaleLinearly :: Property
prop_metricsScaleLinearly = withTests 20 $ property $ do
    baseCount <- forAll $ Gen.int (Range.linear 100 500)
    multiplier <- forAll $ Gen.int (Range.linear 2 5)
    
    store <- evalIO newMetricsStore
    
    let totalCount = baseCount * multiplier
    
    evalIO $ forM_ [1..totalCount] $ \_ -> do
        startTime <- recordRequest store
        recordRequestComplete store startTime
    
    metrics <- evalIO $ getMetrics store
    
    mRequestsTotal metrics === fromIntegral totalCount

-- | Latency bucket recording should be accurate
prop_latencyRecordingAccurate :: Property
prop_latencyRecordingAccurate = withTests 30 $ property $ do
    -- Record latencies in known ranges and verify buckets
    numFast <- forAll $ Gen.int (Range.linear 10 100)    -- < 5ms
    numSlow <- forAll $ Gen.int (Range.linear 10 100)    -- > 1s
    
    store <- evalIO newMetricsStore
    
    -- Record fast latencies (1ms = 0.001s) to Triton
    evalIO $ forM_ [1..numFast] $ \_ -> do
        startTime <- recordRequest store
        recordProviderRequest store Triton
        recordLatency store Triton 0.001  -- 1ms
        recordRequestComplete store startTime
    
    -- Record slow latencies (2s) to Venice
    evalIO $ forM_ [1..numSlow] $ \_ -> do
        startTime <- recordRequest store
        recordProviderRequest store Venice
        recordLatency store Venice 2.0  -- 2 seconds
        recordRequestComplete store startTime
    
    metrics <- evalIO $ getMetrics store
    
    -- Check provider metrics
    case Map.lookup Triton (mProviders metrics) of
        Just pm -> do
            -- Fast requests should be in low buckets
            let lb = pmLatency pm
            -- 1ms falls in <= 5ms bucket
            assert $ lbLe005 lb >= fromIntegral numFast
        Nothing -> failure
    
    case Map.lookup Venice (mProviders metrics) of
        Just pm -> do
            -- Slow requests should NOT be in low buckets
            let lb = pmLatency pm
            -- 2s should be in <= 2.5s bucket but not lower
            assert $ lbLe25s lb >= fromIntegral numSlow
            assert $ lbLe1 lb == 0  -- 2s is NOT <= 100ms
        Nothing -> failure
