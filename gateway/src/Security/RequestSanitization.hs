-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                               // straylight-llm // security/requestsanitization
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE StrictData #-}

module Security.RequestSanitization
    ( -- * Validation Results
      ValidationResult (ValidationOK, ValidationControlCharacters, ValidationNullBytes, ValidationExcessiveLength)
    
      -- * Sanitization
    , sanitizeText
    , validateText
    ) where

import Data.Char (isControl)
import Data.Text (Text)
import Data.Text qualified as T


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Result of request validation
data ValidationResult
    = ValidationOK
    | ValidationControlCharacters !Text
    | ValidationNullBytes
    | ValidationExcessiveLength !Int
    deriving (Show, Eq)


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // sanitization
-- ════════════════════════════════════════════════════════════════════════════

-- | Maximum text length (1MB)
maxTextLength :: Int
maxTextLength = 1024 * 1024

-- | Sanitize text by removing control characters (except newline/tab)
--
-- SECURITY: Strips dangerous control characters that could be used for:
-- - Terminal escape sequences
-- - ANSI code injection
-- - Null byte attacks
-- - Non-printable character injection
sanitizeText :: Text -> Text
sanitizeText = T.filter isSafeChar
  where
    isSafeChar c = not (isControl c) || c == '\n' || c == '\t'

-- | Validate text for security issues
--
-- SECURITY: Checks for:
-- - Null bytes (path truncation attacks)
-- - Dangerous control characters
-- - Excessive length (DoS prevention)
validateText :: Text -> ValidationResult
validateText txt
    | T.length txt > maxTextLength = ValidationExcessiveLength (T.length txt)
    | T.any (== '\0') txt = ValidationNullBytes
    | T.any isDangerousControl txt = ValidationControlCharacters "Contains dangerous control characters"
    | otherwise = ValidationOK
  where
    isDangerousControl c = isControl c && c /= '\n' && c /= '\t'
