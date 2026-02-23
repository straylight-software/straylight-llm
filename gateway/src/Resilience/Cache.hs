-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                       // straylight-llm // resilience/cache
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "They damaged his nervous system with a wartime Russian mycotoxin."
--
--                                                              — Neuromancer
--
-- Bounded LRU cache with TTL for proof storage and other uses.
--
-- Features:
--   - O(1) lookup, insert, delete
--   - LRU eviction when size limit exceeded
--   - Optional TTL expiry
--   - Thread-safe via MVar
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Resilience.Cache
    ( -- * Cache
      BoundedCache
    , CacheConfig (CacheConfig, ccMaxSize, ccTTL)
    , defaultCacheConfig
    
      -- * Construction
    , newBoundedCache
    
      -- * Operations
    , cacheInsert
    , cacheLookup
    , cacheDelete
    , cacheSize
    , cacheRecentValues
    
      -- * Stats
    , CacheStats (CacheStats, csSize, csMaxSize, csHits, csMisses, csEvictions, csHitRate)
    , getCacheStats
    ) where

import Control.Concurrent.MVar
import Data.IORef
import Data.Map.Strict (Map)
import Data.Time.Clock (UTCTime, getCurrentTime, NominalDiffTime, diffUTCTime)

import Data.Map.Strict qualified as Map


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Cache configuration
data CacheConfig = CacheConfig
    { ccMaxSize :: !Int                     -- Maximum number of entries
    , ccTTL :: !(Maybe NominalDiffTime)     -- Optional TTL for entries
    }
    deriving (Eq, Show)

-- | Default cache configuration
defaultCacheConfig :: CacheConfig
defaultCacheConfig = CacheConfig
    { ccMaxSize = 1000
    , ccTTL = Just 3600     -- 1 hour TTL
    }

-- | A cached entry with metadata
data CacheEntry v = CacheEntry
    { ceValue :: !v
    , ceInsertedAt :: !UTCTime
    , ceAccessedAt :: !UTCTime
    , ceAccessCount :: !Int
    }

-- | Internal cache state
data CacheState k v = CacheState
    { csEntries :: !(Map k (CacheEntry v))
    , csInsertOrder :: ![k]    -- Oldest first, for LRU eviction
    }

-- | Thread-safe bounded cache
data BoundedCache k v = BoundedCache
    { bcConfig :: !CacheConfig
    , bcState :: !(MVar (CacheState k v))
    , bcHits :: !(IORef Int)
    , bcMisses :: !(IORef Int)
    , bcEvictions :: !(IORef Int)
    }

-- | Cache statistics
data CacheStats = CacheStats
    { csSize :: !Int
    , csMaxSize :: !Int
    , csHits :: !Int
    , csMisses :: !Int
    , csEvictions :: !Int
    , csHitRate :: !Double      -- Hits / (Hits + Misses)
    }
    deriving (Eq, Show)


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // construction
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a new bounded cache
newBoundedCache :: CacheConfig -> IO (BoundedCache k v)
newBoundedCache config = do
    stateVar <- newMVar CacheState
        { csEntries = Map.empty
        , csInsertOrder = []
        }
    hits <- newIORef 0
    misses <- newIORef 0
    evictions <- newIORef 0
    pure BoundedCache
        { bcConfig = config
        , bcState = stateVar
        , bcHits = hits
        , bcMisses = misses
        , bcEvictions = evictions
        }


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // operations
-- ════════════════════════════════════════════════════════════════════════════

-- | Insert a value into the cache
cacheInsert :: Ord k => BoundedCache k v -> k -> v -> IO ()
cacheInsert cache key value = do
    now <- getCurrentTime
    let entry = CacheEntry
            { ceValue = value
            , ceInsertedAt = now
            , ceAccessedAt = now
            , ceAccessCount = 0
            }
    
    modifyMVar_ (bcState cache) $ \st -> do
        -- Check if we need to evict
        let currentSize = Map.size (csEntries st)
            maxSize = ccMaxSize (bcConfig cache)
        
        st' <- if currentSize >= maxSize && not (Map.member key (csEntries st))
            then evictOldest cache st
            else pure st
        
        -- Insert the new entry
        let newEntries = Map.insert key entry (csEntries st')
            -- Update insert order (remove if exists, add to end)
            newOrder = filter (/= key) (csInsertOrder st') ++ [key]
        
        pure CacheState
            { csEntries = newEntries
            , csInsertOrder = newOrder
            }

-- | Look up a value in the cache
cacheLookup :: Ord k => BoundedCache k v -> k -> IO (Maybe v)
cacheLookup cache key = do
    now <- getCurrentTime
    result <- modifyMVar (bcState cache) $ \st ->
        case Map.lookup key (csEntries st) of
            Nothing ->
                pure (st, Nothing)
            Just entry ->
                -- Check TTL
                case ccTTL (bcConfig cache) of
                    Just ttl | diffUTCTime now (ceInsertedAt entry) > ttl -> do
                        -- Expired - remove it
                        let st' = st { csEntries = Map.delete key (csEntries st)
                                     , csInsertOrder = filter (/= key) (csInsertOrder st)
                                     }
                        pure (st', Nothing)
                    _ -> do
                        -- Valid - update access time and return
                        let entry' = entry { ceAccessedAt = now
                                           , ceAccessCount = ceAccessCount entry + 1
                                           }
                            st' = st { csEntries = Map.insert key entry' (csEntries st) }
                        pure (st', Just (ceValue entry'))
    
    -- Update stats
    case result of
        Nothing -> atomicModifyIORef' (bcMisses cache) $ \n -> (n + 1, ())
        Just _ -> atomicModifyIORef' (bcHits cache) $ \n -> (n + 1, ())
    
    pure result

-- | Delete a value from the cache
cacheDelete :: Ord k => BoundedCache k v -> k -> IO ()
cacheDelete cache key =
    modifyMVar_ (bcState cache) $ \st ->
        pure st { csEntries = Map.delete key (csEntries st)
                , csInsertOrder = filter (/= key) (csInsertOrder st)
                }

-- | Get current cache size
cacheSize :: BoundedCache k v -> IO Int
cacheSize cache = do
    st <- readMVar (bcState cache)
    pure $ Map.size (csEntries st)

-- | Get recent values (most recent first)
-- Returns at most n values, ordered from newest to oldest
cacheRecentValues :: Ord k => BoundedCache k v -> Int -> IO [v]
cacheRecentValues cache n = do
    st <- readMVar (bcState cache)
    -- csInsertOrder is oldest-first, so we reverse and take n
    let recentKeys = take n $ reverse $ csInsertOrder st
    pure $ mapMaybe (\k -> ceValue <$> Map.lookup k (csEntries st)) recentKeys
  where
    mapMaybe :: (a -> Maybe b) -> [a] -> [b]
    mapMaybe _ [] = []
    mapMaybe f (x:xs) = case f x of
        Nothing -> mapMaybe f xs
        Just y  -> y : mapMaybe f xs

-- | Evict the oldest entry
evictOldest :: Ord k => BoundedCache k v -> CacheState k v -> IO (CacheState k v)
evictOldest cache st =
    case csInsertOrder st of
        [] -> pure st  -- Nothing to evict
        (oldest:rest) -> do
            atomicModifyIORef' (bcEvictions cache) $ \n -> (n + 1, ())
            pure st { csEntries = Map.delete oldest (csEntries st)
                    , csInsertOrder = rest
                    }


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // stats
-- ════════════════════════════════════════════════════════════════════════════

-- | Get cache statistics
getCacheStats :: BoundedCache k v -> IO CacheStats
getCacheStats cache = do
    st <- readMVar (bcState cache)
    hits <- readIORef (bcHits cache)
    misses <- readIORef (bcMisses cache)
    evictions <- readIORef (bcEvictions cache)
    let total = hits + misses
        hitRate = if total == 0 then 0.0 else fromIntegral hits / fromIntegral total
    pure CacheStats
        { csSize = Map.size (csEntries st)
        , csMaxSize = ccMaxSize (bcConfig cache)
        , csHits = hits
        , csMisses = misses
        , csEvictions = evictions
        , csHitRate = hitRate
        }
