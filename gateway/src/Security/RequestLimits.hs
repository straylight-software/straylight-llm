-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                    // straylight-llm // security/requestlimits
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE StrictData #-}

-- |
-- Module      : Security.RequestLimits
-- Description : DoS prevention via request size and count limits
-- License     : MIT
--
-- Request limits to prevent denial of service attacks:
--
-- - Maximum request body size
-- - Maximum number of messages in chat request
-- - Maximum tokens per request
-- - Maximum string length per message
--
-- Reference: COMPASS GHSA-j27p-hq53-9wgc (DoS via unbounded fetch)
module Security.RequestLimits
    ( -- * Limit Configuration
      RequestLimits
        ( RequestLimits
        , rlMaxBodyBytes
        , rlMaxMessages
        , rlMaxTokens
        , rlMaxMessageLength
        , rlMaxTotalContentLength
        )
    , defaultRequestLimits
    , strictRequestLimits
    
      -- * Limit Checking
    , LimitViolation
        ( LimitOK
        , BodyTooLarge
        , TooManyMessages
        , TokenLimitExceeded
        , MessageTooLong
        , TotalContentTooLong
        )
    , checkBodySize
    , checkMessageCount
    , checkTokenLimit
    , checkMessageLength
    , checkTotalContentLength
    
      -- * Aggregate Checking
    , checkAllLimits
    ) where

import Data.Word (Word64)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Configuration for request limits
data RequestLimits = RequestLimits
    { rlMaxBodyBytes :: !Word64
      -- ^ Maximum request body size in bytes (default: 10 MB)
    , rlMaxMessages :: !Int
      -- ^ Maximum number of messages in chat request (default: 1000)
    , rlMaxTokens :: !Int
      -- ^ Maximum tokens per request (default: 128000)
    , rlMaxMessageLength :: !Int
      -- ^ Maximum length of a single message content (default: 1 MB)
    , rlMaxTotalContentLength :: !Int
      -- ^ Maximum total content length across all messages (default: 10 MB)
    }
    deriving (Show, Eq)

-- | Result of limit checking
data LimitViolation
    = LimitOK
    | BodyTooLarge !Word64 !Word64
      -- ^ (actual, limit)
    | TooManyMessages !Int !Int
      -- ^ (actual, limit)
    | TokenLimitExceeded !Int !Int
      -- ^ (actual, limit)
    | MessageTooLong !Int !Int
      -- ^ (actual, limit)
    | TotalContentTooLong !Int !Int
      -- ^ (actual, limit)
    deriving (Show, Eq)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // defaults
-- ════════════════════════════════════════════════════════════════════════════

-- | Default limits suitable for most use cases
--
-- - Body: 10 MB
-- - Messages: 1000
-- - Tokens: 128000 (typical large context window)
-- - Message length: 1 MB
-- - Total content: 10 MB
defaultRequestLimits :: RequestLimits
defaultRequestLimits = RequestLimits
    { rlMaxBodyBytes = 10 * 1024 * 1024
    , rlMaxMessages = 1000
    , rlMaxTokens = 128000
    , rlMaxMessageLength = 1024 * 1024
    , rlMaxTotalContentLength = 10 * 1024 * 1024
    }

-- | Strict limits for high-security environments
--
-- - Body: 1 MB
-- - Messages: 100
-- - Tokens: 8192
-- - Message length: 100 KB
-- - Total content: 1 MB
strictRequestLimits :: RequestLimits
strictRequestLimits = RequestLimits
    { rlMaxBodyBytes = 1 * 1024 * 1024
    , rlMaxMessages = 100
    , rlMaxTokens = 8192
    , rlMaxMessageLength = 100 * 1024
    , rlMaxTotalContentLength = 1 * 1024 * 1024
    }


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // checking
-- ════════════════════════════════════════════════════════════════════════════

-- | Check if request body size is within limits
--
-- SECURITY: Prevents memory exhaustion from oversized request bodies.
checkBodySize :: RequestLimits -> Word64 -> LimitViolation
checkBodySize limits actual
    | actual <= rlMaxBodyBytes limits = LimitOK
    | otherwise = BodyTooLarge actual (rlMaxBodyBytes limits)

-- | Check if message count is within limits
--
-- SECURITY: Prevents DoS via excessive message arrays that consume
-- processing time and memory.
checkMessageCount :: RequestLimits -> Int -> LimitViolation
checkMessageCount limits actual
    | actual <= rlMaxMessages limits = LimitOK
    | otherwise = TooManyMessages actual (rlMaxMessages limits)

-- | Check if token count is within limits
--
-- SECURITY: Prevents expensive API calls with excessive token counts
-- that could result in high costs or provider rate limits.
checkTokenLimit :: RequestLimits -> Int -> LimitViolation
checkTokenLimit limits actual
    | actual <= rlMaxTokens limits = LimitOK
    | otherwise = TokenLimitExceeded actual (rlMaxTokens limits)

-- | Check if a single message length is within limits
--
-- SECURITY: Prevents memory exhaustion from single oversized messages.
checkMessageLength :: RequestLimits -> Int -> LimitViolation
checkMessageLength limits actual
    | actual <= rlMaxMessageLength limits = LimitOK
    | otherwise = MessageTooLong actual (rlMaxMessageLength limits)

-- | Check if total content length is within limits
--
-- SECURITY: Prevents aggregate content size attacks where many
-- smaller messages combine to exhaust memory.
checkTotalContentLength :: RequestLimits -> Int -> LimitViolation
checkTotalContentLength limits actual
    | actual <= rlMaxTotalContentLength limits = LimitOK
    | otherwise = TotalContentTooLong actual (rlMaxTotalContentLength limits)


-- ════════════════════════════════════════════════════════════════════════════
--                                                       // aggregate checking
-- ════════════════════════════════════════════════════════════════════════════

-- | Check all applicable limits at once
--
-- Returns the first violation found, or LimitOK if all pass.
-- Checks in order of severity/cost:
-- 1. Body size (cheapest to check, prevents further processing)
-- 2. Message count
-- 3. Total content length
-- 4. Token limit (if provided)
checkAllLimits 
    :: RequestLimits 
    -> Word64        -- ^ Body size in bytes
    -> Int           -- ^ Number of messages
    -> Int           -- ^ Total content length
    -> Maybe Int     -- ^ Optional token count (if known)
    -> LimitViolation
checkAllLimits limits bodySize messageCount totalContent maybeTokens =
    case checkBodySize limits bodySize of
        LimitOK -> case checkMessageCount limits messageCount of
            LimitOK -> case checkTotalContentLength limits totalContent of
                LimitOK -> case maybeTokens of
                    Just tokens -> checkTokenLimit limits tokens
                    Nothing -> LimitOK
                violation -> violation
            violation -> violation
        violation -> violation
