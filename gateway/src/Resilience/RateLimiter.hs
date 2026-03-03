{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData #-}

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                  // straylight-llm // resilience/ratelimiter
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Time passed. The construct flickered. Zero smiled."
--
--                                                              — Neuromancer
--
-- Token bucket rate limiter for per-API-key rate limiting.
--
-- Uses the token bucket algorithm:
-- - Each bucket has a capacity (max tokens) and refill rate (tokens/second)
-- - Each request consumes one token
-- - Tokens refill continuously up to capacity
-- - If no tokens available, request is rejected (429)
--
-- Features:
-- - Per-key buckets with lazy creation
-- - Configurable default limits
-- - Per-key limit overrides
-- - Automatic cleanup of expired buckets
-- - Thread-safe via STM
--
-- Configuration via environment:
--   RATE_LIMIT_ENABLED=true       Enable rate limiting
--   RATE_LIMIT_RPM=60             Requests per minute (default)
--   RATE_LIMIT_BURST=10           Burst capacity above RPM
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

module Resilience.RateLimiter
  ( -- * Configuration
    RateLimitConfig (..),
    defaultRateLimitConfig,
    loadRateLimitConfig,

    -- * Rate Limiter
    RateLimiter,
    newRateLimiter,

    -- * Rate Limiting Operations
    RateLimitResult (..),
    checkRateLimit,
    consumeToken,
    getRemainingTokens,
    getResetSeconds,

    -- * Per-Key Configuration
    KeyLimits (..),
    setKeyLimits,
    removeKeyLimits,

    -- * Observability
    RateLimiterStats (..),
    getRateLimiterStats,
    getKeyStats,

    -- * WAI Middleware
    rateLimitMiddleware,
  )
where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.STM
  ( STM,
    TVar,
    atomically,
    modifyTVar',
    newTVarIO,
    readTVar,
    readTVarIO,
    writeTVar,
  )
import Control.Monad (forever, void, when)
import Data.Aeson (ToJSON (toJSON), encode, object, (.=))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text, pack)
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import GHC.Generics (Generic)
import Network.HTTP.Types (hContentType, status429)
import Network.Wai (Middleware, Request, mapResponseHeaders, requestHeaders, responseLBS)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // configuration
-- ════════════════════════════════════════════════════════════════════════════

-- | Rate limit configuration
data RateLimitConfig = RateLimitConfig
  { -- | Whether rate limiting is enabled
    rlcEnabled :: !Bool,
    -- | Default requests per minute per key
    rlcRequestsPerMinute :: !Int,
    -- | Burst capacity (extra tokens above steady state)
    rlcBurstCapacity :: !Int,
    -- | How often to clean up expired buckets
    rlcCleanupIntervalSeconds :: !Int,
    -- | How long before an unused bucket is cleaned up
    rlcBucketExpirySeconds :: !Int
  }
  deriving (Show, Eq, Generic)

instance ToJSON RateLimitConfig where
  toJSON RateLimitConfig {..} =
    object
      [ "enabled" .= rlcEnabled,
        "requests_per_minute" .= rlcRequestsPerMinute,
        "burst_capacity" .= rlcBurstCapacity,
        "cleanup_interval_seconds" .= rlcCleanupIntervalSeconds,
        "bucket_expiry_seconds" .= rlcBucketExpirySeconds
      ]

-- | Default rate limit configuration
defaultRateLimitConfig :: RateLimitConfig
defaultRateLimitConfig =
  RateLimitConfig
    { rlcEnabled = False, -- Disabled by default
      rlcRequestsPerMinute = 60, -- 1 request/second sustained
      rlcBurstCapacity = 10, -- Allow bursts of 10
      rlcCleanupIntervalSeconds = 300, -- Cleanup every 5 minutes
      rlcBucketExpirySeconds = 3600 -- Expire after 1 hour of inactivity
    }

-- | Load rate limit configuration from environment
loadRateLimitConfig :: IO RateLimitConfig
loadRateLimitConfig = do
  enabled <- maybe False (== "true") <$> lookupEnv "RATE_LIMIT_ENABLED"
  rpm <- maybe 60 id . (>>= readMaybe) <$> lookupEnv "RATE_LIMIT_RPM"
  burst <- maybe 10 id . (>>= readMaybe) <$> lookupEnv "RATE_LIMIT_BURST"

  pure
    defaultRateLimitConfig
      { rlcEnabled = enabled,
        rlcRequestsPerMinute = rpm,
        rlcBurstCapacity = burst
      }

-- ════════════════════════════════════════════════════════════════════════════
--                                                              // token bucket
-- ════════════════════════════════════════════════════════════════════════════

-- | A single token bucket for one API key
data TokenBucket = TokenBucket
  { -- | Current number of tokens (can be fractional during refill)
    tbTokens :: !Double,
    -- | Maximum token capacity
    tbCapacity :: !Double,
    -- | Tokens added per second
    tbRefillRate :: !Double,
    -- | Last time tokens were refilled
    tbLastRefill :: !UTCTime,
    -- | Last time this bucket was accessed (for cleanup)
    tbLastAccess :: !UTCTime
  }
  deriving (Show, Eq, Generic)

-- | Per-key limit overrides
data KeyLimits = KeyLimits
  { klRequestsPerMinute :: !Int,
    klBurstCapacity :: !Int
  }
  deriving (Show, Eq, Generic)

instance ToJSON KeyLimits where
  toJSON KeyLimits {..} =
    object
      [ "requests_per_minute" .= klRequestsPerMinute,
        "burst_capacity" .= klBurstCapacity
      ]

-- ════════════════════════════════════════════════════════════════════════════
--                                                              // rate limiter
-- ════════════════════════════════════════════════════════════════════════════

-- | The rate limiter - holds all buckets and configuration
data RateLimiter = RateLimiter
  { rlConfig :: !RateLimitConfig,
    rlBuckets :: !(TVar (Map Text TokenBucket)),
    rlKeyLimits :: !(TVar (Map Text KeyLimits)),
    rlStats :: !(TVar RateLimiterStats)
  }

-- | Result of a rate limit check
data RateLimitResult
  = -- | Allowed: remaining tokens, reset time in seconds
    RateLimitAllowed !Int !Int
  | -- | Exceeded: retry after N seconds
    RateLimitExceeded !Int
  deriving (Show, Eq, Generic)

instance ToJSON RateLimitResult where
  toJSON (RateLimitAllowed remaining reset) =
    object
      [ "allowed" .= True,
        "remaining_tokens" .= remaining,
        "reset_seconds" .= reset
      ]
  toJSON (RateLimitExceeded retryAfter) =
    object
      [ "allowed" .= False,
        "retry_after_seconds" .= retryAfter
      ]

-- | Get remaining tokens from result (for header generation)
getRemainingTokens :: RateLimitResult -> Int
getRemainingTokens (RateLimitAllowed remaining _) = remaining
getRemainingTokens (RateLimitExceeded _) = 0

-- | Get reset/retry time from result (for header generation)
getResetSeconds :: RateLimitResult -> Int
getResetSeconds (RateLimitAllowed _ reset) = reset
getResetSeconds (RateLimitExceeded retryAfter) = retryAfter

-- | Statistics for observability
data RateLimiterStats = RateLimiterStats
  { rlsActiveBuckets :: !Int,
    rlsTotalChecks :: !Int,
    rlsTotalAllowed :: !Int,
    rlsTotalRejected :: !Int
  }
  deriving (Show, Eq, Generic)

instance ToJSON RateLimiterStats where
  toJSON RateLimiterStats {..} =
    object
      [ "active_buckets" .= rlsActiveBuckets,
        "total_checks" .= rlsTotalChecks,
        "total_allowed" .= rlsTotalAllowed,
        "total_rejected" .= rlsTotalRejected
      ]

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // construction
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a new rate limiter
newRateLimiter :: RateLimitConfig -> IO RateLimiter
newRateLimiter config = do
  buckets <- newTVarIO Map.empty
  keyLimits <- newTVarIO Map.empty
  stats <- newTVarIO (RateLimiterStats 0 0 0 0)

  let limiter =
        RateLimiter
          { rlConfig = config,
            rlBuckets = buckets,
            rlKeyLimits = keyLimits,
            rlStats = stats
          }

  -- Start cleanup thread if enabled
  when (rlcEnabled config) $
    void $
      forkIO $
        cleanupLoop limiter

  pure limiter

-- | Background cleanup of expired buckets
cleanupLoop :: RateLimiter -> IO ()
cleanupLoop limiter = forever $ do
  threadDelay (rlcCleanupIntervalSeconds (rlConfig limiter) * 1000000)
  now <- getCurrentTime
  atomically $ do
    buckets <- readTVar (rlBuckets limiter)
    let expiryTime = fromIntegral (rlcBucketExpirySeconds (rlConfig limiter))
        isExpired bucket = diffUTCTime now (tbLastAccess bucket) > expiryTime
        activeBuckets = Map.filter (not . isExpired) buckets
    writeTVar (rlBuckets limiter) activeBuckets
    modifyTVar' (rlStats limiter) $ \s ->
      s {rlsActiveBuckets = Map.size activeBuckets}

-- ════════════════════════════════════════════════════════════════════════════
--                                                              // operations
-- ════════════════════════════════════════════════════════════════════════════

-- | Check rate limit for a key (doesn't consume token)
checkRateLimit :: RateLimiter -> Text -> IO RateLimitResult
checkRateLimit limiter apiKey = do
  if not (rlcEnabled (rlConfig limiter))
    then pure (RateLimitAllowed 999 0) -- Unlimited when disabled
    else do
      now <- getCurrentTime
      atomically $ checkRateLimitSTM limiter apiKey now False

-- | Consume a token for a key (returns result and consumes if allowed)
consumeToken :: RateLimiter -> Text -> IO RateLimitResult
consumeToken limiter apiKey = do
  if not (rlcEnabled (rlConfig limiter))
    then pure (RateLimitAllowed 999 0) -- Unlimited when disabled
    else do
      now <- getCurrentTime
      atomically $ checkRateLimitSTM limiter apiKey now True

-- | STM implementation of rate limit check
checkRateLimitSTM :: RateLimiter -> Text -> UTCTime -> Bool -> STM RateLimitResult
checkRateLimitSTM limiter apiKey now consume = do
  buckets <- readTVar (rlBuckets limiter)
  keyLimitsMap <- readTVar (rlKeyLimits limiter)

  -- Get or create bucket for this key
  let mBucket = Map.lookup apiKey buckets
      keyLimit = Map.lookup apiKey keyLimitsMap
      (capacity, refillRate) = getLimits limiter keyLimit

  bucket <- case mBucket of
    Just b -> pure $ refillBucket b now
    Nothing -> pure $ newBucket capacity refillRate now

  -- Update stats
  modifyTVar' (rlStats limiter) $ \s ->
    s {rlsTotalChecks = rlsTotalChecks s + 1}

  if tbTokens bucket >= 1.0
    then do
      -- Allowed
      let updatedBucket =
            if consume
              then bucket {tbTokens = tbTokens bucket - 1.0, tbLastAccess = now}
              else bucket {tbLastAccess = now}
          newBuckets = Map.insert apiKey updatedBucket buckets
      writeTVar (rlBuckets limiter) newBuckets
      modifyTVar' (rlStats limiter) $ \s ->
        s
          { rlsTotalAllowed = rlsTotalAllowed s + 1,
            rlsActiveBuckets = Map.size newBuckets
          }
      let remaining = floor (tbTokens updatedBucket)
          resetSeconds = ceiling (tbCapacity bucket / tbRefillRate bucket)
      pure (RateLimitAllowed remaining resetSeconds)
    else do
      -- Rate limited
      let tokensNeeded = 1.0 - tbTokens bucket
          retryAfter = ceiling (tokensNeeded / tbRefillRate bucket)
          newBuckets = Map.insert apiKey (bucket {tbLastAccess = now}) buckets
      writeTVar (rlBuckets limiter) newBuckets
      modifyTVar' (rlStats limiter) $ \s ->
        s
          { rlsTotalRejected = rlsTotalRejected s + 1,
            rlsActiveBuckets = Map.size newBuckets
          }
      pure (RateLimitExceeded retryAfter)

-- | Get limits for a key (custom or default)
getLimits :: RateLimiter -> Maybe KeyLimits -> (Double, Double)
getLimits limiter mKeyLimits =
  let config = rlConfig limiter
      (rpm, burst) = case mKeyLimits of
        Just kl -> (klRequestsPerMinute kl, klBurstCapacity kl)
        Nothing -> (rlcRequestsPerMinute config, rlcBurstCapacity config)
      capacity = fromIntegral (rpm + burst)
      refillRate = fromIntegral rpm / 60.0 -- tokens per second
   in (capacity, refillRate)

-- | Create a new bucket with full capacity
newBucket :: Double -> Double -> UTCTime -> TokenBucket
newBucket capacity refillRate now =
  TokenBucket
    { tbTokens = capacity, -- Start full
      tbCapacity = capacity,
      tbRefillRate = refillRate,
      tbLastRefill = now,
      tbLastAccess = now
    }

-- | Refill a bucket based on elapsed time
refillBucket :: TokenBucket -> UTCTime -> TokenBucket
refillBucket bucket now =
  let elapsed = realToFrac (diffUTCTime now (tbLastRefill bucket)) :: Double
      newTokens = tbTokens bucket + (elapsed * tbRefillRate bucket)
      cappedTokens = min newTokens (tbCapacity bucket)
   in bucket {tbTokens = cappedTokens, tbLastRefill = now}

-- ════════════════════════════════════════════════════════════════════════════
--                                                        // per-key management
-- ════════════════════════════════════════════════════════════════════════════

-- | Set custom limits for a specific API key
setKeyLimits :: RateLimiter -> Text -> KeyLimits -> IO ()
setKeyLimits limiter apiKey limits =
  atomically $
    modifyTVar' (rlKeyLimits limiter) (Map.insert apiKey limits)

-- | Remove custom limits for a key (reverts to default)
removeKeyLimits :: RateLimiter -> Text -> IO ()
removeKeyLimits limiter apiKey =
  atomically $
    modifyTVar' (rlKeyLimits limiter) (Map.delete apiKey)

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // observability
-- ════════════════════════════════════════════════════════════════════════════

-- | Get overall rate limiter stats
getRateLimiterStats :: RateLimiter -> IO RateLimiterStats
getRateLimiterStats limiter = readTVarIO (rlStats limiter)

-- | Get stats for a specific key
getKeyStats :: RateLimiter -> Text -> IO (Maybe (Int, Int))
getKeyStats limiter apiKey = do
  buckets <- readTVarIO (rlBuckets limiter)
  pure $ case Map.lookup apiKey buckets of
    Just bucket -> Just (floor (tbTokens bucket), floor (tbCapacity bucket))
    Nothing -> Nothing

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // wai middleware
-- ════════════════════════════════════════════════════════════════════════════

-- | WAI middleware for rate limiting
--
-- Extracts the API key from the Authorization header (Bearer token)
-- and enforces rate limits. Returns 429 Too Many Requests when exceeded.
rateLimitMiddleware :: RateLimiter -> Middleware
rateLimitMiddleware limiter app req respond = do
  let mApiKey = extractApiKey req
  case mApiKey of
    Nothing ->
      -- No API key - let the request through (auth middleware will reject if needed)
      app req respond
    Just apiKey -> do
      result <- consumeToken limiter apiKey
      case result of
        RateLimitAllowed remaining reset -> do
          -- Add rate limit headers and continue
          let rateLimitHeaders =
                [ ("X-RateLimit-Remaining", TE.encodeUtf8 $ showText remaining),
                  ("X-RateLimit-Reset", TE.encodeUtf8 $ showText reset)
                ]
          app req $ \response ->
            respond $ mapResponseHeaders (<> rateLimitHeaders) response
        RateLimitExceeded retryAfter -> do
          -- Return 429 Too Many Requests
          let body =
                encode $
                  object
                    [ "error" .= ("rate_limit_exceeded" :: Text),
                      "message" .= ("Too many requests. Please retry after " <> showText retryAfter <> " seconds." :: Text),
                      "retry_after" .= retryAfter
                    ]
              headers =
                [ (hContentType, "application/json"),
                  ("Retry-After", TE.encodeUtf8 $ showText retryAfter),
                  ("X-RateLimit-Remaining", "0"),
                  ("X-RateLimit-Reset", TE.encodeUtf8 $ showText retryAfter)
                ]
          respond $ responseLBS status429 headers body

-- | Extract API key from Authorization header
--
-- Supports "Bearer <token>" format, extracts the token.
extractApiKey :: Request -> Maybe Text
extractApiKey req =
  case lookup "Authorization" (requestHeaders req) of
    Just authHeader -> extractBearerToken authHeader
    Nothing -> Nothing

-- | Extract bearer token from Authorization header value
extractBearerToken :: ByteString -> Maybe Text
extractBearerToken header =
  case BS.stripPrefix "Bearer " header of
    Just token -> Just $ TE.decodeUtf8 token
    Nothing ->
      -- Try lowercase
      case BS.stripPrefix "bearer " header of
        Just token -> Just $ TE.decodeUtf8 token
        Nothing -> Nothing

-- | Show helper for Text conversion
showText :: (Show a) => a -> Text
showText = pack . show
