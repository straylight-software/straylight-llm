-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                    // straylight-llm // security/constanttime
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE StrictData #-}

module Security.ConstantTime
    ( -- * Constant-Time Comparison
      constantTimeCompare
    , constantTimeCompareText
    ) where

import Data.Bits (xor)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // comparison
-- ════════════════════════════════════════════════════════════════════════════

-- | Constant-time comparison of two ByteStrings.
--
-- SECURITY: This function compares ALL bytes regardless of where mismatches
-- occur, preventing timing attacks that could leak information about token
-- values character-by-character.
--
-- Reference: COMPASS GHSA-jmm5-fvh5-gf4p (Non-constant-time token comparison)
constantTimeCompare :: ByteString -> ByteString -> Bool
constantTimeCompare a b
    | BS.length a /= BS.length b = False
    | otherwise = (== 0) $ foldl xor (0 :: Word8) $ BS.zipWith xor a b
{-# NOINLINE constantTimeCompare #-}

-- | Constant-time comparison for Text values.
--
-- Encodes to UTF-8 then uses constant-time ByteString comparison.
constantTimeCompareText :: Text -> Text -> Bool
constantTimeCompareText a b =
    constantTimeCompare (TE.encodeUtf8 a) (TE.encodeUtf8 b)
{-# NOINLINE constantTimeCompareText #-}
