-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                       // straylight-llm // resilience/retry
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The sky above the port was the color of television,
--      tuned to a dead channel."
--
--                                                              — Neuromancer
--
-- Retry logic with exponential backoff and jitter.
--
-- Key features:
--   - Exponential backoff: delay doubles with each retry
--   - Jitter: random variation prevents thundering herd
--   - Configurable max retries and delays
--   - Respects Retry-After headers
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Resilience.Retry
    ( -- * Retry Config
      RetryConfig (RetryConfig, rcMaxRetries, rcBaseDelay, rcMaxDelay, rcBackoffMultiplier, rcJitterFactor)
    , defaultRetryConfig
    
      -- * Retry Logic
    , withRetryBackoff
    , calculateBackoff
    , addJitter
    
      -- * Delay Parsing
    , parseRetryAfter
    ) where

import Control.Concurrent (threadDelay)
import Data.Text (Text)
import Data.Time.Clock (NominalDiffTime)
import System.Random (randomRIO)

import Data.Text qualified as T
import Text.Read (readMaybe)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Retry configuration
data RetryConfig = RetryConfig
    { rcMaxRetries :: !Int              -- Maximum number of retries
    , rcBaseDelay :: !NominalDiffTime   -- Initial delay (e.g., 1 second)
    , rcMaxDelay :: !NominalDiffTime    -- Maximum delay cap
    , rcBackoffMultiplier :: !Double    -- Multiplier for exponential backoff
    , rcJitterFactor :: !Double         -- Jitter as fraction of delay (0.0-1.0)
    }
    deriving (Eq, Show)

-- | Sensible defaults for LLM API calls
defaultRetryConfig :: RetryConfig
defaultRetryConfig = RetryConfig
    { rcMaxRetries = 3
    , rcBaseDelay = 1.0                 -- 1 second initial delay
    , rcMaxDelay = 60.0                 -- Cap at 60 seconds
    , rcBackoffMultiplier = 2.0         -- Double each time
    , rcJitterFactor = 0.25             -- ±25% jitter
    }


-- ════════════════════════════════════════════════════════════════════════════
--                                                             // retry logic
-- ════════════════════════════════════════════════════════════════════════════

-- | Execute an action with exponential backoff retry
--
-- The action should return:
--   Right result - Success, stop retrying
--   Left (retryable, error) - Failure; if retryable, retry; otherwise stop
--
-- The retryAfter parameter allows respecting Retry-After headers.
--
withRetryBackoff :: RetryConfig 
                 -> (Int -> IO (Either (Bool, Maybe NominalDiffTime, e) a))  -- ^ Action with attempt number
                 -> IO (Either e a)
withRetryBackoff config action = go 0
  where
    go attempt
        | attempt > rcMaxRetries config = do
            -- Out of retries, make one last attempt
            result <- action attempt
            pure $ case result of
                Right a -> Right a
                Left (_, _, e) -> Left e
        | otherwise = do
            result <- action attempt
            case result of
                Right a -> pure $ Right a
                Left (retryable, mRetryAfter, e)
                    | not retryable -> pure $ Left e
                    | otherwise -> do
                        -- Calculate delay with backoff
                        let baseDelay = calculateBackoff config attempt
                        -- Respect Retry-After if provided
                        let delay = maybe baseDelay (max baseDelay) mRetryAfter
                        -- Add jitter
                        jitteredDelay <- addJitter config delay
                        -- Wait
                        threadDelay $ nominalToMicros jitteredDelay
                        -- Retry
                        go (attempt + 1)

-- | Calculate exponential backoff delay for given attempt
calculateBackoff :: RetryConfig -> Int -> NominalDiffTime
calculateBackoff config attempt =
    let multiplied = rcBaseDelay config * (realToFrac (rcBackoffMultiplier config) ^ attempt)
    in min multiplied (rcMaxDelay config)

-- | Add random jitter to a delay
--
-- Jitter prevents thundering herd when many clients retry simultaneously.
-- The jitter is a random value in the range [-factor*delay, +factor*delay].
--
addJitter :: RetryConfig -> NominalDiffTime -> IO NominalDiffTime
addJitter config delay = do
    let factor = rcJitterFactor config
        minDelay = delay * realToFrac (1.0 - factor)
        maxDelay = delay * realToFrac (1.0 + factor)
    -- Generate random delay in range
    jittered <- randomRIO (nominalToDouble minDelay, nominalToDouble maxDelay)
    pure $ realToFrac jittered


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // header parsing
-- ════════════════════════════════════════════════════════════════════════════

-- | Parse a Retry-After header value
--
-- Can be either:
--   - A number of seconds (e.g., "120")
--   - An HTTP-date (e.g., "Wed, 21 Oct 2015 07:28:00 GMT") - not yet supported
--
parseRetryAfter :: Text -> Maybe NominalDiffTime
parseRetryAfter headerValue =
    -- Try parsing as integer seconds first
    case readMaybe (T.unpack $ T.strip headerValue) :: Maybe Int of
        Just seconds -> Just $ fromIntegral seconds
        Nothing -> 
            -- Could add HTTP-date parsing here
            Nothing


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Convert NominalDiffTime to microseconds for threadDelay
nominalToMicros :: NominalDiffTime -> Int
nominalToMicros t = round (t * 1000000)

-- | Convert NominalDiffTime to Double
nominalToDouble :: NominalDiffTime -> Double
nominalToDouble = realToFrac
