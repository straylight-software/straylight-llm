-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                          // straylight-llm // security/observabilitysanitization
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE StrictData #-}

-- |
-- Module      : Security.ObservabilitySanitization
-- Description : Sanitize observability data to prevent information leakage
-- License     : MIT
--
-- Observability endpoints can leak sensitive information if not properly
-- sanitized. This module provides functions to:
--
-- - Hash request IDs to prevent correlation attacks
-- - Round metrics to prevent timing side channels
-- - Redact sensitive headers and parameters
-- - Truncate request/response bodies
--
-- SECURITY: Observability data is often exposed to operators or monitoring
-- systems with different trust levels than the production system. Careful
-- sanitization prevents:
--
-- - Request correlation across systems
-- - Timing attacks via precise metrics
-- - PII leakage in request bodies
-- - API key exposure in headers
module Security.ObservabilitySanitization
    ( -- * Request ID Handling
      hashRequestId
    , truncateRequestId
    
      -- * Metrics Sanitization
    , roundLatency
    , roundTokenCount
    , LatencyBucket
        ( LatencyFast
        , LatencyNormal
        , LatencySlow
        , LatencyVerySlow
        , LatencyTimeout
        )
    , bucketLatency
    
      -- * Header Sanitization
    , sanitizeHeaders
    , sensitiveHeaderNames
    
      -- * Body Sanitization
    , truncateBody
    , hashBody
    , maxObservableBodyLength
    
      -- * Full Request Sanitization
    , SanitizedRequest
        ( SanitizedRequest
        , srRequestIdHash
        , srMethod
        , srPath
        , srLatencyBucket
        , srTokenCount
        , srProvider
        , srModel
        , srStatus
        )
    , sanitizeRequest
    ) where

import Crypto.Hash (SHA256, Digest, hash)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as B16
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Latency buckets for observability
--
-- SECURITY: Exact latencies can enable timing attacks. Bucketing provides
-- useful operational insight while preventing precise timing information.
data LatencyBucket
    = LatencyFast       -- ^ < 100ms
    | LatencyNormal     -- ^ 100ms - 500ms
    | LatencySlow       -- ^ 500ms - 2000ms
    | LatencyVerySlow   -- ^ 2000ms - 10000ms
    | LatencyTimeout    -- ^ > 10000ms
    deriving (Show, Eq, Ord)

-- | A sanitized request for observability purposes
data SanitizedRequest = SanitizedRequest
    { srRequestIdHash :: !Text
      -- ^ SHA256 hash of the original request ID (first 16 chars)
    , srMethod :: !Text
      -- ^ HTTP method
    , srPath :: !Text
      -- ^ Request path (without query params)
    , srLatencyBucket :: !LatencyBucket
      -- ^ Bucketed latency
    , srTokenCount :: !Int
      -- ^ Rounded token count
    , srProvider :: !Text
      -- ^ Provider name
    , srModel :: !Text
      -- ^ Model name
    , srStatus :: !Int
      -- ^ HTTP status code
    }
    deriving (Show, Eq)


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // request id
-- ════════════════════════════════════════════════════════════════════════════

-- | Hash a request ID for observability
--
-- SECURITY: Raw request IDs can be used to correlate requests across
-- different systems or logs. Hashing prevents this while still allowing
-- deduplication within a single system.
hashRequestId :: Text -> Text
hashRequestId requestId =
    T.take 16 $ TE.decodeUtf8 $ B16.encode $ BS.pack $ BS.unpack digestBytes
  where
    digestBytes :: ByteString
    digestBytes = BS.pack $ BS.unpack $ hashToBytes $ hash $ TE.encodeUtf8 requestId
    
    hashToBytes :: Digest SHA256 -> ByteString
    hashToBytes d = BS.pack $ BS.unpack $ TE.encodeUtf8 $ T.pack $ show d

-- | Truncate a request ID to first N characters
--
-- SECURITY: Alternative to hashing - just show partial ID.
truncateRequestId :: Int -> Text -> Text
truncateRequestId n = T.take n


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // metrics
-- ════════════════════════════════════════════════════════════════════════════

-- | Round latency to nearest 10ms
--
-- SECURITY: Prevents precise timing information that could enable
-- timing attacks or reveal processing patterns.
roundLatency :: Int -> Int
roundLatency ms = (ms `div` 10) * 10

-- | Round token count to nearest 10
--
-- SECURITY: Prevents exact token counts that could be used to
-- fingerprint specific prompts or responses.
roundTokenCount :: Int -> Int
roundTokenCount tokens = (tokens `div` 10) * 10

-- | Convert latency to a bucket
--
-- SECURITY: More aggressive than rounding - only reveals order of magnitude.
bucketLatency :: Int -> LatencyBucket
bucketLatency ms
    | ms < 100 = LatencyFast
    | ms < 500 = LatencyNormal
    | ms < 2000 = LatencySlow
    | ms < 10000 = LatencyVerySlow
    | otherwise = LatencyTimeout


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // headers
-- ════════════════════════════════════════════════════════════════════════════

-- | Headers that should never appear in observability data
sensitiveHeaderNames :: [Text]
sensitiveHeaderNames =
    [ "authorization"
    , "x-api-key"
    , "api-key"
    , "x-auth-token"
    , "cookie"
    , "set-cookie"
    , "x-csrf-token"
    , "x-request-id"      -- May contain correlation info
    , "x-correlation-id"
    , "x-trace-id"
    ]

-- | Remove sensitive headers from a list
--
-- SECURITY: API keys, tokens, and correlation IDs should never appear
-- in observability data.
sanitizeHeaders :: [(Text, Text)] -> [(Text, Text)]
sanitizeHeaders = filter (not . isSensitive . fst)
  where
    isSensitive name = T.toLower name `elem` sensitiveHeaderNames


-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // body
-- ════════════════════════════════════════════════════════════════════════════

-- | Maximum body length to include in observability data (1KB)
maxObservableBodyLength :: Int
maxObservableBodyLength = 1024

-- | Truncate body for observability
--
-- SECURITY: Full request/response bodies may contain PII, API keys,
-- or sensitive business data. Truncating limits exposure.
truncateBody :: Text -> Text
truncateBody body
    | T.length body <= maxObservableBodyLength = body
    | otherwise = T.take maxObservableBodyLength body <> "[truncated]"

-- | Hash body for observability
--
-- SECURITY: When body content shouldn't be visible at all, use a hash
-- to allow deduplication without revealing content.
hashBody :: ByteString -> Text
hashBody body = T.take 16 $ TE.decodeUtf8 $ B16.encode digestBytes
  where
    digestBytes :: ByteString
    digestBytes = BS.pack $ BS.unpack $ hashToBytes $ hash body
    
    hashToBytes :: Digest SHA256 -> ByteString
    hashToBytes d = BS.pack $ BS.unpack $ TE.encodeUtf8 $ T.pack $ show d


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // full sanitization
-- ════════════════════════════════════════════════════════════════════════════

-- | Sanitize a request for observability
--
-- Applies all sanitization rules to create a safe representation.
sanitizeRequest
    :: Text    -- ^ Original request ID
    -> Text    -- ^ HTTP method
    -> Text    -- ^ Request path (will have query params stripped)
    -> Int     -- ^ Latency in ms
    -> Int     -- ^ Token count
    -> Text    -- ^ Provider name
    -> Text    -- ^ Model name
    -> Int     -- ^ HTTP status code
    -> SanitizedRequest
sanitizeRequest requestId method path latency tokens provider model status =
    SanitizedRequest
        { srRequestIdHash = hashRequestId requestId
        , srMethod = method
        , srPath = stripQueryParams path
        , srLatencyBucket = bucketLatency latency
        , srTokenCount = roundTokenCount tokens
        , srProvider = provider
        , srModel = model
        , srStatus = status
        }
  where
    stripQueryParams = T.takeWhile (/= '?')
