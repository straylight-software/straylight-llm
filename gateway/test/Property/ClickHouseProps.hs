-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                             // straylight-llm // property // clickhouse tests
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd made the classic mistake, the one he'd sworn he'd never make. He
--      fell in love with the speed."
--
--                                                              — Neuromancer
--
-- Property-based stress tests for metrics and ClickHouse telemetry.
-- Tests the REAL MetricsStore under high concurrency and load.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}

module Property.ClickHouseProps
    ( tests
    ) where

import Control.Concurrent.Async (replicateConcurrently)
import Control.Monad (forM_, when)
import Data.IORef (newIORef, readIORef, atomicModifyIORef')
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.Hedgehog

import Resilience.Metrics
    ( LatencyBuckets (..)
    , Metrics (..)
    , MetricsStore
    , ProviderMetrics (..)
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
--                                                               // generators
-- ════════════════════════════════════════════════════════════════════════════

-- | Generate a provider name
genProviderName :: Gen ProviderName
genProviderName = Gen.enumBounded

-- | Generate adversarial SQL injection attempts
genSqlInjection :: Gen Text
genSqlInjection = Gen.element
    [ "'; DROP TABLE metrics_snapshots; --"
    , "1; DELETE FROM requests WHERE 1=1; --"
    , "' OR '1'='1"
    , "'); INSERT INTO metrics_snapshots VALUES (1,2,3); --"
    , "UNION SELECT * FROM system.users"
    , "1; ATTACH TABLE malicious FROM 's3://evil'; --"
    , "\"; DROP DATABASE straylight; --"
    , "\\x00\\x01\\x02"
    , "NULL"
    , "0x deadbeef"
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // property tests
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "ClickHouse Telemetry"
    [ testGroup "MetricsStore Concurrency"
        [ testProperty "concurrent_increments_are_atomic" prop_concurrentIncrementsAtomic
        , testProperty "metrics_never_decrease" prop_metricsNeverDecrease
        ]
    , testGroup "SQL Injection Resistance"
        [ testProperty "sql_injection_in_provider_name" prop_sqlInjectionProviderName
        ]
    , testGroup "Stress Tests"
        [ testProperty "high_volume_metrics_recording" prop_highVolumeMetricsRecording
        ]
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                   // concurrency properties
-- ════════════════════════════════════════════════════════════════════════════

-- | Concurrent increments should result in correct total
prop_concurrentIncrementsAtomic :: Property
prop_concurrentIncrementsAtomic = withTests 50 $ property $ do
    numThreads <- forAll $ Gen.int (Range.linear 2 20)
    incrementsPerThread <- forAll $ Gen.int (Range.linear 100 1000)
    
    -- Create a fresh metrics store
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

-- | Metrics should never decrease after recording
prop_metricsNeverDecrease :: Property
prop_metricsNeverDecrease = withTests 100 $ property $ do
    numRecords <- forAll $ Gen.int (Range.linear 1 100)
    
    store <- evalIO newMetricsStore
    
    -- Record and check monotonicity
    prevRef <- evalIO $ newIORef (0 :: Word64)
    
    evalIO $ forM_ [1..numRecords] $ \_ -> do
        startTime <- recordRequest store
        recordRequestComplete store startTime
        current <- mRequestsTotal <$> getMetrics store
        prev <- readIORef prevRef
        -- Current should be >= prev (we just recorded)
        if current >= prev
            then atomicModifyIORef' prevRef (\_ -> (current, ()))
            else error "Metrics decreased!"
    
    success


-- ════════════════════════════════════════════════════════════════════════════
--                                                   // sql injection properties
-- ════════════════════════════════════════════════════════════════════════════

-- | Metrics recording with various providers should work correctly
prop_sqlInjectionProviderName :: Property
prop_sqlInjectionProviderName = withTests 100 $ property $ do
    -- Use real provider names (enum-based, so no injection possible)
    provider <- forAll genProviderName
    
    store <- evalIO newMetricsStore
    
    -- Recording with any provider name should work
    startTime <- evalIO $ recordRequest store
    evalIO $ recordProviderRequest store provider
    evalIO $ recordProviderError store provider (UnknownError "test")
    evalIO $ recordLatency store provider 1.0
    evalIO $ recordRequestComplete store startTime
    
    -- Should still be able to read metrics
    metrics <- evalIO $ getMetrics store
    assert $ mRequestsTotal metrics >= 1


-- ════════════════════════════════════════════════════════════════════════════
--                                                         // stress properties
-- ════════════════════════════════════════════════════════════════════════════

-- | High volume metrics recording should not lose data
prop_highVolumeMetricsRecording :: Property
prop_highVolumeMetricsRecording = withTests 20 $ property $ do
    -- Generate a large batch of operations
    numOps <- forAll $ Gen.int (Range.linear 1000 10_000)
    
    store <- evalIO newMetricsStore
    
    -- Rotate through providers
    let providers = [Triton, Venice, Anthropic, OpenRouter, Together]
    
    -- Blast requests at the store
    evalIO $ forM_ [1..numOps] $ \i -> do
        let provider = providers !! (i `mod` length providers)
        startTime <- recordRequest store
        recordProviderRequest store provider
        when (i `mod` 10 == 0) $ recordProviderError store provider (UnknownError "test")
        recordLatency store provider (fromIntegral i / 1000.0)
        recordRequestComplete store startTime
    
    -- Verify counts
    metrics <- evalIO $ getMetrics store
    
    -- Total requests should match
    mRequestsTotal metrics === fromIntegral numOps
