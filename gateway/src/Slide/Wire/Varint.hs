{- | LEB128 varint encoding for SIGIL wire format

Variable-length integer encoding where each byte uses 7 bits for data
and 1 bit as continuation flag. Used for extended token IDs.
-}
module Slide.Wire.Varint (
    -- * Encoding
    encodeVarint,
    encodeVarintBuilder,
    pokeVarint,

    -- * Decoding
    decodeVarint,

    -- * Size calculation
    varintSize,
) where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as Builder
import Data.Word (Word32, Word8)
import Foreign.Ptr (Ptr)
import Foreign.Storable (pokeByteOff)

-- ════════════════════════════════════════════════════════════════════════════════
-- Encoding
-- ════════════════════════════════════════════════════════════════════════════════

-- | Encode Word32 as LEB128 varint ByteString
encodeVarint :: Word32 -> ByteString
encodeVarint = BS.pack . encodeVarintBytes
{-# INLINE encodeVarint #-}

encodeVarintBytes :: Word32 -> [Word8]
encodeVarintBytes !value
    | value < 0x80 = [fromIntegral value]
    | otherwise =
        fromIntegral (value .&. 0x7F .|. 0x80)
            : encodeVarintBytes (value `shiftR` 7)

-- | Encode as Builder (for efficient concatenation)
encodeVarintBuilder :: Word32 -> Builder.Builder
encodeVarintBuilder = encodeVarintBuilderLoop
  where
    encodeVarintBuilderLoop :: Word32 -> Builder.Builder
    encodeVarintBuilderLoop !value
        | value < 0x80 = Builder.word8 (fromIntegral value)
        | otherwise =
            Builder.word8 (fromIntegral (value .&. 0x7F .|. 0x80))
                <> encodeVarintBuilderLoop (value `shiftR` 7)
{-# INLINE encodeVarintBuilder #-}

-- | Write varint to pointer, return bytes written
pokeVarint :: Ptr Word8 -> Word32 -> IO Int
pokeVarint pointer = pokeVarintLoop 0
  where
    pokeVarintLoop :: Int -> Word32 -> IO Int
    pokeVarintLoop !byteOffset !value
        | value < 0x80 = do
            pokeByteOff pointer byteOffset (fromIntegral value :: Word8)
            pure (byteOffset + 1)
        | otherwise = do
            pokeByteOff pointer byteOffset (fromIntegral (value .&. 0x7F .|. 0x80) :: Word8)
            pokeVarintLoop (byteOffset + 1) (value `shiftR` 7)
{-# INLINE pokeVarint #-}

-- ════════════════════════════════════════════════════════════════════════════════
-- Decoding
-- ════════════════════════════════════════════════════════════════════════════════

-- | Decode varint from ByteString, return (value, bytes consumed)
decodeVarint :: ByteString -> Maybe (Word32, Int)
decodeVarint byteString = decodeVarintLoop 0 0 0
  where
    decodeVarintLoop :: Word32 -> Int -> Int -> Maybe (Word32, Int)
    decodeVarintLoop !accumulator !bitShift !byteOffset
        | byteOffset >= BS.length byteString = Nothing
        | otherwise =
            let currentByte = BS.index byteString byteOffset
                newValue = accumulator .|. (fromIntegral (currentByte .&. 0x7F) `shiftL` bitShift)
             in if currentByte .&. 0x80 == 0
                    then Just (newValue, byteOffset + 1)
                    else
                        if bitShift >= 28
                            then Nothing -- overflow protection for Word32
                            else decodeVarintLoop newValue (bitShift + 7) (byteOffset + 1)
{-# INLINE decodeVarint #-}

-- ════════════════════════════════════════════════════════════════════════════════
-- Size Calculation
-- ════════════════════════════════════════════════════════════════════════════════

-- | Calculate encoded size of varint
varintSize :: Word32 -> Int
varintSize value
    | value < 0x80 = 1
    | value < 0x4000 = 2
    | value < 0x20_0000 = 3
    | value < 0x1000_0000 = 4
    | otherwise = 5
{-# INLINE varintSize #-}
