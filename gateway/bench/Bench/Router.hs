-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                      // straylight-llm // bench/Router.hs
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- Router performance benchmarks.
--
-- Tests:
--   - Request ID generation throughput
--   - Proof cache insertion/lookup
--   - Request history cache operations
--   - Concurrent routing overhead
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE BangPatterns #-}

module Bench.Router (benchmarks) where

import Control.Concurrent.Async (replicateConcurrently_)
import Control.DeepSeq (NFData (rnf))
import Control.Monad (replicateM_, forM_)
import Criterion.Main
    ( Benchmark
    , bench
    , bgroup
    , nfIO
    , whnfIO
    )
import Data.IORef (IORef, newIORef, atomicModifyIORef', readIORef, writeIORef)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import Numeric (showHex)
import System.IO.Unsafe (unsafePerformIO)
import System.Random (randomIO)

import Resilience.Cache 
    ( BoundedCache
    , CacheConfig (ccMaxSize)
    , defaultCacheConfig
    , newBoundedCache
    , cacheInsert
    , cacheLookup
    )


-- | All router benchmarks
benchmarks :: Benchmark
benchmarks = bgroup "Router"
    [ requestIdBenchmarks
    , proofCacheBenchmarks
    , concurrentRoutingBenchmarks
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                    // request id generation
-- ════════════════════════════════════════════════════════════════════════════

-- | Generate a unique request ID (same as Router.generateRequestId)
generateRequestId :: IO Text
generateRequestId = do
    n <- randomIO :: IO Word64
    pure $! "req_" <> T.pack (showHex n "")

requestIdBenchmarks :: Benchmark
requestIdBenchmarks = bgroup "RequestId"
    [ bench "generate/single" $ nfIO generateRequestId
    , bench "generate/100" $ nfIO (replicateM_ 100 generateRequestId)
    , bench "generate/1000" $ nfIO (replicateM_ 1000 generateRequestId)
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // proof cache
-- ════════════════════════════════════════════════════════════════════════════

-- | Simulated proof data (just a placeholder for benchmarking)
data MockProof = MockProof !Text !Int
    deriving (Eq, Show)

instance NFData MockProof where
    rnf (MockProof t i) = rnf t `seq` rnf i

-- | Create a mock proof cache (Map-based, like Router)
type ProofCache = Map.Map Text MockProof

-- | Global refs for caches (avoids NFData requirement for env)
{-# NOINLINE mapCacheRef #-}
mapCacheRef :: IORef (Maybe (IORef ProofCache))
mapCacheRef = unsafePerformIO $ newIORef Nothing

{-# NOINLINE boundedCacheRef #-}
boundedCacheRef :: IORef (Maybe (BoundedCache Text MockProof))
boundedCacheRef = unsafePerformIO $ newIORef Nothing

-- | Get or create map-based proof cache
getMapCache :: IO (IORef ProofCache)
getMapCache = do
    mcache <- readIORef mapCacheRef
    case mcache of
        Just cache -> pure cache
        Nothing -> do
            ref <- newIORef Map.empty
            -- Pre-populate with some entries
            forM_ [0..999 :: Int] $ \i -> do
                let reqId = "req_" <> T.pack (show i)
                atomicModifyIORef' ref $ \cache ->
                    (Map.insert reqId (MockProof reqId i) cache, ())
            -- Add known entry
            atomicModifyIORef' ref $ \cache ->
                (Map.insert "req_known" (MockProof "req_known" 999) cache, ())
            writeIORef mapCacheRef (Just ref)
            pure ref

-- | Get or create bounded cache
getBoundedCache :: IO (BoundedCache Text MockProof)
getBoundedCache = do
    mcache <- readIORef boundedCacheRef
    case mcache of
        Just cache -> pure cache
        Nothing -> do
            cache <- newBoundedCache defaultCacheConfig { ccMaxSize = 5000 }
            -- Pre-populate
            forM_ [0..999 :: Int] $ \i -> do
                let reqId = "req_" <> T.pack (show i)
                cacheInsert cache reqId (MockProof reqId i)
            writeIORef boundedCacheRef (Just cache)
            pure cache

proofCacheBenchmarks :: Benchmark
proofCacheBenchmarks = bgroup "ProofCache"
    [ bgroup "Map-based"
        [ bench "insert/single" $ whnfIO $ do
            cacheRef <- getMapCache
            reqId <- generateRequestId
            atomicModifyIORef' cacheRef $ \cache ->
                (Map.insert reqId (MockProof reqId 42) cache, ())
        , bench "lookup/hit" $ whnfIO $ do
            cacheRef <- getMapCache
            cache <- readIORef cacheRef
            let !result = Map.lookup "req_known" cache
            pure result
        , bench "lookup/miss" $ whnfIO $ do
            cacheRef <- getMapCache
            cache <- readIORef cacheRef
            let !result = Map.lookup "req_unknown_xyz" cache
            pure result
        ]
    , bgroup "BoundedCache"
        [ bench "insert/single" $ whnfIO $ do
            cache <- getBoundedCache
            reqId <- generateRequestId
            cacheInsert cache reqId (MockProof reqId 42)
        , bench "lookup/existing" $ whnfIO $ do
            cache <- getBoundedCache
            cacheLookup cache "req_0"
        , bench "lookup/missing" $ whnfIO $ do
            cache <- getBoundedCache
            cacheLookup cache "req_unknown_xyz"
        ]
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // concurrent routing
-- ════════════════════════════════════════════════════════════════════════════

-- | Global ref for concurrent benchmark cache
{-# NOINLINE concurrentCacheRef #-}
concurrentCacheRef :: IORef (Maybe (BoundedCache Text MockProof))
concurrentCacheRef = unsafePerformIO $ newIORef Nothing

-- | Get or create concurrent benchmark cache
getConcurrentCache :: IO (BoundedCache Text MockProof)
getConcurrentCache = do
    mcache <- readIORef concurrentCacheRef
    case mcache of
        Just cache -> pure cache
        Nothing -> do
            cache <- newBoundedCache defaultCacheConfig { ccMaxSize = 10000 }
            forM_ [0..999 :: Int] $ \i -> do
                let reqId = "req_" <> T.pack (show i)
                cacheInsert cache reqId (MockProof reqId i)
            writeIORef concurrentCacheRef (Just cache)
            pure cache

concurrentRoutingBenchmarks :: Benchmark
concurrentRoutingBenchmarks = bgroup "Concurrent"
    [ bench "requestId/10-concurrent" $ nfIO $
        replicateConcurrently_ 10 generateRequestId
    , bench "requestId/100-concurrent" $ nfIO $
        replicateConcurrently_ 100 generateRequestId
    , bgroup "cache"
        [ bench "insert/10-concurrent" $ nfIO $ do
            cache <- getConcurrentCache
            replicateConcurrently_ 10 $ do
                reqId <- generateRequestId
                cacheInsert cache reqId (MockProof reqId 1)
        , bench "insert/100-concurrent" $ nfIO $ do
            cache <- getConcurrentCache
            replicateConcurrently_ 100 $ do
                reqId <- generateRequestId
                cacheInsert cache reqId (MockProof reqId 1)
        , bench "lookup/100-concurrent" $ nfIO $ do
            cache <- getConcurrentCache
            replicateConcurrently_ 100 $
                cacheLookup cache "req_0"
        ]
    ]
