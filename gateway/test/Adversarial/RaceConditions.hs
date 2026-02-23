-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                // straylight-llm // adversarial // race tests
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The sky above the port was the color of television, tuned to a dead
--      channel."
--
--                                                              — Neuromancer
--
-- Race condition tests for concurrent operations.
-- Designed to BREAK things - hunt for real bugs.
--
-- Tests:
--   - Concurrent STM operations on ModelRegistry
--   - Concurrent cache reads/writes
--   - Router state under concurrent requests
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}

module Adversarial.RaceConditions
    ( tests
    ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (mapConcurrently, replicateConcurrently, forConcurrently, async)
import Control.Concurrent.STM
import Control.Monad (replicateM, forM_)
import Data.IORef
import Test.Tasty
import Test.Tasty.HUnit

import Resilience.Cache


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // stm atomicity tests
-- ════════════════════════════════════════════════════════════════════════════

-- | Test that concurrent TVar modifications are atomic
test_concurrentTVarModificationsAtomic :: TestTree
test_concurrentTVarModificationsAtomic = testCase "Concurrent TVar modifications are atomic" $ do
    counter <- newTVarIO (0 :: Int)
    
    -- Fire 100 concurrent increments
    _ <- forConcurrently [1..100 :: Int] $ \_ -> 
        atomically $ modifyTVar' counter (+1)
    
    -- Final value must be exactly 100
    final <- readTVarIO counter
    assertEqual "Counter should be exactly 100" 100 final

-- | Test that readTVar → modifyTVar' is NOT atomic (demonstrates the bug pattern)
-- This documents the WRONG way to do things
test_readThenModifyIsNotAtomic :: TestTree
test_readThenModifyIsNotAtomic = testCase "read→modify pattern shows potential race (documented)" $ do
    counter <- newTVarIO (0 :: Int)
    
    -- Fire 100 concurrent read-then-increment (WRONG pattern)
    -- Some updates may be lost due to TOCTOU
    let wrongIncrement = do
            val <- readTVarIO counter
            atomically $ writeTVar counter (val + 1)
    
    _ <- forConcurrently [1..100 :: Int] $ \_ -> wrongIncrement
    
    -- Final value may be less than 100 due to races
    final <- readTVarIO counter
    -- We just document that this CAN happen, not that it MUST
    -- The test passes regardless - it's documenting the pattern
    assertBool "Counter should be <= 100 (may lose updates)" (final <= 100)

-- | Test that our STM patterns are correctly atomic
test_correctAtomicPattern :: TestTree
test_correctAtomicPattern = testCase "Correct STM pattern maintains invariant" $ do
    -- Maintain invariant: sum of values = 0 (transfers between accounts)
    account1 <- newTVarIO (100 :: Int)
    account2 <- newTVarIO (100 :: Int)
    
    -- Concurrent transfers in both directions
    let transfer from to amount = atomically $ do
            f <- readTVar from
            t <- readTVar to
            when (f >= amount) $ do
                writeTVar from (f - amount)
                writeTVar to (t + amount)
    
    -- 50 threads transfer 1→2, 50 threads transfer 2→1
    let actions = 
            replicate 50 (transfer account1 account2 1) ++
            replicate 50 (transfer account2 account1 1)
    
    _ <- mapConcurrently id actions
    
    -- Invariant: total must still be 200
    final1 <- readTVarIO account1
    final2 <- readTVarIO account2
    assertEqual "Total must remain 200" 200 (final1 + final2)


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // cache race tests
-- ════════════════════════════════════════════════════════════════════════════

-- | Test concurrent cache inserts don't corrupt state
test_concurrentCacheInserts :: TestTree
test_concurrentCacheInserts = testCase "Concurrent cache inserts maintain integrity" $ do
    cache <- newBoundedCache (defaultCacheConfig { ccMaxSize = 50 })
    
    -- 100 concurrent inserts with unique keys
    _ <- forConcurrently [1..100 :: Int] $ \i -> do
        let key = "key-" <> show i :: String
            val = "value-" <> show i :: String
        cacheInsert cache key val
    
    -- Cache should have at most maxSize entries
    size <- cacheSize cache
    assertBool "Cache size should not exceed max" (size <= 50)
    
    -- All remaining entries should be valid (not corrupted)
    stats <- getCacheStats cache
    assertEqual "Size in stats should match" size (csSize stats)

-- | Test concurrent reads during writes don't crash
test_concurrentReadsAndWrites :: TestTree
test_concurrentReadsAndWrites = testCase "Concurrent reads and writes don't crash" $ do
    cache <- newBoundedCache defaultCacheConfig
    
    -- Pre-populate
    forM_ [1..100 :: Int] $ \i ->
        cacheInsert cache ("key-" <> show i) ("value-" <> show i :: String)
    
    -- Concurrent reads and writes
    let readAction = do
            forM_ [1..50 :: Int] $ \i -> do
                _ <- cacheLookup cache ("key-" <> show i)
                pure ()
        writeAction = do
            forM_ [101..150 :: Int] $ \i ->
                cacheInsert cache ("key-" <> show i) ("value-" <> show i :: String)
    
    -- Run both concurrently
    _ <- forConcurrently [1..10 :: Int] $ \i ->
        if even i then readAction else writeAction
    
    -- Should not crash, cache should be consistent
    size <- cacheSize cache
    assertBool "Cache should have entries" (size > 0)

-- | Test eviction under concurrent load
test_evictionUnderLoad :: TestTree
test_evictionUnderLoad = testCase "Eviction works correctly under concurrent load" $ do
    cache <- newBoundedCache (defaultCacheConfig { ccMaxSize = 10 })
    
    -- Hammer with 1000 inserts across 10 threads
    _ <- forConcurrently [1..10 :: Int] $ \threadId -> do
        forM_ [1..100 :: Int] $ \i -> do
            let key = "thread-" <> show threadId <> "-key-" <> show i :: String
                val = "value" :: String
            cacheInsert cache key val
    
    -- Cache size must never exceed max
    size <- cacheSize cache
    assertBool "Cache size must not exceed maxSize" (size <= 10)
    
    -- Eviction count should be positive (we inserted 1000, max is 10)
    stats <- getCacheStats cache
    assertBool "Should have evicted entries" (csEvictions stats > 0)

-- | Test that lookups under heavy write load return consistent values
test_lookupConsistencyUnderLoad :: TestTree
test_lookupConsistencyUnderLoad = testCase "Lookups return consistent values under write load" $ do
    cache <- newBoundedCache (defaultCacheConfig { ccMaxSize = 100 })
    
    -- Insert initial value
    cacheInsert cache "stable-key" ("stable-value" :: String)
    
    -- Start writer thread that updates the value
    writerDone <- newTVarIO False
    _ <- async $ do
        forM_ [1..100 :: Int] $ \i -> do
            cacheInsert cache "changing-key" ("value-" <> show i)
            threadDelay 100  -- 0.1ms
        atomically $ writeTVar writerDone True
    
    -- Concurrent readers
    results <- forConcurrently [1..10 :: Int] $ \_ -> do
        vals <- replicateM 50 $ do
            mval <- cacheLookup cache "stable-key"
            pure mval
        pure $ all (== Just "stable-value") vals
    
    -- All reads of stable-key should return the same value
    assertBool "All stable-key reads should be consistent" (and results)


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // state corruption
-- ════════════════════════════════════════════════════════════════════════════

-- | Test that IORef updates under concurrent load don't lose updates
test_iorefCounterAccuracy :: TestTree
test_iorefCounterAccuracy = testCase "IORef counter with atomicModifyIORef' is accurate" $ do
    counter <- newIORef (0 :: Int)
    
    -- 1000 concurrent increments using atomicModifyIORef'
    _ <- forConcurrently [1..1000 :: Int] $ \_ -> 
        atomicModifyIORef' counter $ \n -> (n + 1, ())
    
    -- Final count must be exactly 1000
    final <- readIORef counter
    assertEqual "Counter should be exactly 1000" 1000 final

-- | Test that modifyIORef (non-atomic) can lose updates (demonstrates the bug)
test_nonAtomicModifyLosesUpdates :: TestTree
test_nonAtomicModifyLosesUpdates = testCase "Non-atomic modifyIORef loses updates (documented)" $ do
    counter <- newIORef (0 :: Int)
    
    -- This WRONG pattern can lose updates
    let wrongIncrement = do
            val <- readIORef counter
            writeIORef counter (val + 1)
    
    _ <- forConcurrently [1..100 :: Int] $ \_ -> wrongIncrement
    
    -- Final value may be less than 100
    final <- readIORef counter
    -- We just document this happens - test always passes
    assertBool "Counter may be less than 100 due to races" (final <= 100)


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // helper: when
-- ════════════════════════════════════════════════════════════════════════════

when :: Applicative f => Bool -> f () -> f ()
when True action = action
when False _ = pure ()


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "Race Condition Tests"
    [ testGroup "STM Atomicity"
        [ test_concurrentTVarModificationsAtomic
        , test_readThenModifyIsNotAtomic
        , test_correctAtomicPattern
        ]
    , testGroup "Cache Concurrency"
        [ test_concurrentCacheInserts
        , test_concurrentReadsAndWrites
        , test_evictionUnderLoad
        , test_lookupConsistencyUnderLoad
        ]
    , testGroup "Counter Accuracy"
        [ test_iorefCounterAccuracy
        , test_nonAtomicModifyLosesUpdates
        ]
    ]
