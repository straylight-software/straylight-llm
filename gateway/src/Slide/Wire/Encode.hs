{- | Pure encoding functions for SIGIL wire format

Use these for testing and non-performance-critical paths.
For hot path, use FrameBuilder in Slide.Wire.Frame.
-}
module Slide.Wire.Encode (
    -- * Pure encoding
    encodeHotToken,
    encodeExtendedToken,
    encodeControl,
    encodeToken,

    -- * Batch encoding
    encodeTokenList,
) where

import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as Builder
import Data.ByteString.Lazy qualified as LBS

import Slide.Wire.Types (Frame (..), FrameOp (..), HotId, TokenId)
import Slide.Wire.Varint (encodeVarint, encodeVarintBuilder)

-- ════════════════════════════════════════════════════════════════════════════════
-- Pure Encoding
-- ════════════════════════════════════════════════════════════════════════════════

-- | Encode a hot token as single byte
encodeHotToken :: HotId -> Frame
encodeHotToken hotId = Frame (BS.singleton hotId)
{-# INLINE encodeHotToken #-}

-- | Encode an extended token (0x80 escape + varint)
encodeExtendedToken :: TokenId -> Frame
encodeExtendedToken tokenId = Frame (BS.cons 0x80 (encodeVarint tokenId))
{-# INLINE encodeExtendedToken #-}

-- | Encode a control opcode
encodeControl :: FrameOp -> Frame
encodeControl (FrameOp opcode) = Frame (BS.singleton opcode)
{-# INLINE encodeControl #-}

-- | Encode a token using hot table lookup
encodeToken :: (TokenId -> Maybe HotId) -> TokenId -> Frame
encodeToken hotLookup tokenId = case hotLookup tokenId of
    Just hotId -> encodeHotToken hotId
    Nothing -> encodeExtendedToken tokenId
{-# INLINE encodeToken #-}

-- ════════════════════════════════════════════════════════════════════════════════
-- Batch Encoding
-- ════════════════════════════════════════════════════════════════════════════════

-- | Encode a list of tokens efficiently using Builder
encodeTokenList :: (TokenId -> Maybe HotId) -> [TokenId] -> Frame
encodeTokenList hotLookup tokens =
    Frame $ LBS.toStrict $ Builder.toLazyByteString $ foldMap encodeOneToken tokens
  where
    encodeOneToken :: TokenId -> Builder.Builder
    encodeOneToken tokenId = case hotLookup tokenId of
        Just hotId -> Builder.word8 hotId
        Nothing -> Builder.word8 0x80 <> encodeVarintBuilder tokenId
{-# INLINE encodeTokenList #-}
