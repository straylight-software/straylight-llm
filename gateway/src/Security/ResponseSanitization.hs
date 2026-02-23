-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                              // straylight-llm // security/responsesanitization
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE StrictData #-}

-- |
-- Module      : Security.ResponseSanitization
-- Description : Prevent data leakage in error responses
-- License     : MIT
--
-- Response sanitization to prevent information disclosure:
--
-- - Strip internal paths from error messages
-- - Redact API keys and tokens
-- - Remove stack traces in production
-- - Sanitize exception messages
--
-- SECURITY: Error messages should never expose:
-- - Internal file paths
-- - API keys or tokens
-- - Database connection strings
-- - Stack traces with internal structure
-- - Provider-specific error details that reveal architecture
module Security.ResponseSanitization
    ( -- * Error Sanitization
      sanitizeErrorMessage
    , sanitizeException
    
      -- * Redaction
    , redactApiKey
    , redactPath
    , redactStackTrace
    
      -- * Pattern Detection
    , containsSensitiveData
    , SensitiveDataType
        ( SensitiveApiKey
        , SensitivePath
        , SensitiveStackTrace
        , SensitiveConnectionString
        , SensitiveInternalError
        )
    
      -- * Safe Error Construction
    , safeErrorResponse
    , ErrorSeverity
        ( ErrorClient
        , ErrorServer
        , ErrorProvider
        )
    ) where

import Data.Text (Text)
import Data.Text qualified as T


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Types of sensitive data that may appear in errors
data SensitiveDataType
    = SensitiveApiKey
    | SensitivePath
    | SensitiveStackTrace
    | SensitiveConnectionString
    | SensitiveInternalError
    deriving (Show, Eq, Ord)

-- | Severity level for error responses
data ErrorSeverity
    = ErrorClient      -- ^ Client error (4xx) - safe to expose details
    | ErrorServer      -- ^ Server error (5xx) - hide internal details
    | ErrorProvider    -- ^ Provider error - sanitize but include provider name
    deriving (Show, Eq, Ord)


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // pattern detection
-- ════════════════════════════════════════════════════════════════════════════

-- | Patterns that indicate API keys or tokens
apiKeyPatterns :: [Text]
apiKeyPatterns =
    [ "sk-"              -- OpenAI/Anthropic style
    , "api_key="
    , "apikey="
    , "bearer "
    , "authorization:"
    , "x-api-key:"
    , "token="
    , "access_token="
    , "secret="
    , "password="
    , "credential"
    ]

-- | Patterns that indicate file paths
pathPatterns :: [Text]
pathPatterns =
    [ "/home/"
    , "/usr/"
    , "/var/"
    , "/etc/"
    , "/tmp/"
    , "/root/"
    , "c:\\"
    , "c:/"
    , ".hs:"          -- Haskell source file references
    , ".cabal"
    , "dist-newstyle"
    , "stack-work"
    ]

-- | Patterns that indicate stack traces
stackTracePatterns :: [Text]
stackTracePatterns =
    [ "callstack"
    , "at module"
    , "called from"
    , "ghc:"
    , "exception:"
    , "throwio"
    , "error:"
    , "src/"
    ]

-- | Patterns that indicate connection strings
connectionPatterns :: [Text]
connectionPatterns =
    [ "postgresql://"
    , "postgres://"
    , "mysql://"
    , "mongodb://"
    , "redis://"
    , "host="
    , "dbname="
    , "user="
    ]

-- | Check if text contains sensitive data
containsSensitiveData :: Text -> Maybe SensitiveDataType
containsSensitiveData txt
    | matchesAny apiKeyPatterns = Just SensitiveApiKey
    | matchesAny connectionPatterns = Just SensitiveConnectionString
    | matchesAny stackTracePatterns = Just SensitiveStackTrace
    | matchesAny pathPatterns = Just SensitivePath
    | otherwise = Nothing
  where
    lower = T.toLower txt
    matchesAny patterns = any (`T.isInfixOf` lower) patterns


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // redaction
-- ════════════════════════════════════════════════════════════════════════════

-- | Redact API keys from text
--
-- SECURITY: Replaces API keys with [REDACTED] to prevent exposure in logs
-- or error messages.
redactApiKey :: Text -> Text
redactApiKey txt = foldr redactPattern txt apiKeyPatterns
  where
    redactPattern pattern text =
        if pattern `T.isInfixOf` T.toLower text
            then redactAfterPattern pattern text
            else text
    
    -- Redact content after the pattern until whitespace or quote
    redactAfterPattern pattern text =
        case T.breakOn pattern (T.toLower text) of
            (before, after) 
                | T.null after -> text
                | otherwise -> 
                    let originalBefore = T.take (T.length before) text
                        originalPattern = T.take (T.length pattern) (T.drop (T.length before) text)
                        rest = T.drop (T.length pattern) (T.drop (T.length before) text)
                        (_, afterSensitive) = T.break isSeparator rest
                    in originalBefore <> originalPattern <> "[REDACTED]" <> afterSensitive
    
    isSeparator c = c == ' ' || c == '\n' || c == '\t' || c == '"' || c == '\''

-- | Redact file paths from text
--
-- SECURITY: Replaces internal paths with [PATH] to prevent exposure of
-- server filesystem structure.
redactPath :: Text -> Text
redactPath txt = foldr redactPathPattern txt pathPatterns
  where
    redactPathPattern pattern text =
        if pattern `T.isInfixOf` T.toLower text
            then T.replace pattern "[PATH]" text
            else text

-- | Remove stack traces from text
--
-- SECURITY: Strips Haskell stack traces that reveal internal structure.
redactStackTrace :: Text -> Text
redactStackTrace txt
    | hasStackTrace = "[stack trace redacted]"
    | otherwise = txt
  where
    lower = T.toLower txt
    hasStackTrace = any (`T.isInfixOf` lower) 
        [ "callstack (from hasCallStack)"
        , "ghc.stack"
        , "exception was thrown"
        ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // sanitization
-- ════════════════════════════════════════════════════════════════════════════

-- | Sanitize an error message for external consumption
--
-- SECURITY: Applies all redaction rules to prevent data leakage.
sanitizeErrorMessage :: Text -> Text
sanitizeErrorMessage = redactStackTrace . redactPath . redactApiKey

-- | Sanitize an exception message
--
-- SECURITY: For exceptions, we're more aggressive - if any sensitive
-- data is detected, we replace the entire message with a generic error.
sanitizeException :: Text -> Text
sanitizeException txt =
    case containsSensitiveData txt of
        Just SensitiveApiKey -> "Authentication error"
        Just SensitivePath -> "Internal error"
        Just SensitiveStackTrace -> "Internal error"
        Just SensitiveConnectionString -> "Service unavailable"
        Just SensitiveInternalError -> "Internal error"
        Nothing -> sanitizeErrorMessage txt


-- ════════════════════════════════════════════════════════════════════════════
--                                                     // safe error responses
-- ════════════════════════════════════════════════════════════════════════════

-- | Construct a safe error response based on severity
--
-- SECURITY: Different error severities get different levels of detail:
-- - Client errors: Can include sanitized details to help debugging
-- - Server errors: Generic message only
-- - Provider errors: Include provider name but sanitize details
safeErrorResponse :: ErrorSeverity -> Text -> Text -> Text
safeErrorResponse severity provider rawMessage =
    case severity of
        ErrorClient -> 
            -- Client errors can include more detail
            sanitizeErrorMessage rawMessage
        
        ErrorServer ->
            -- Server errors should be opaque
            "Internal server error"
        
        ErrorProvider ->
            -- Provider errors include provider name
            provider <> ": " <> sanitizeProviderError rawMessage

-- | Sanitize provider-specific error messages
--
-- SECURITY: Removes internal details but keeps user-actionable information.
sanitizeProviderError :: Text -> Text
sanitizeProviderError txt
    | "rate limit" `T.isInfixOf` lower = "Rate limit exceeded"
    | "quota" `T.isInfixOf` lower = "Quota exceeded"
    | "unauthorized" `T.isInfixOf` lower = "Authentication failed"
    | "forbidden" `T.isInfixOf` lower = "Access denied"
    | "not found" `T.isInfixOf` lower = "Resource not found"
    | "timeout" `T.isInfixOf` lower = "Request timed out"
    | "unavailable" `T.isInfixOf` lower = "Service temporarily unavailable"
    | "bad request" `T.isInfixOf` lower = "Invalid request"
    | "invalid" `T.isInfixOf` lower = "Invalid request parameters"
    | otherwise = "Provider error"
  where
    lower = T.toLower txt
