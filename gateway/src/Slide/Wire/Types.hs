{-# LANGUAGE PatternSynonyms #-}

{- | SIGIL wire format types

Encoding scheme (from SIGIL spec):
  0xxxxxxx  = hot token (ID in lower 7 bits, 0x00-0x7E)
  10xxxxxx  = extended token (varint follows)
  1100xxxx  = stream control
  1101xxxx  = reserved
  1110xxxx  = extension
  1111xxxx  = envelope (connection setup, rare)
-}
module Slide.Wire.Types (
    -- * Token types
    TokenId,
    HotId,

    -- * Frame types
    Frame (..),
    FrameOp (..),

    -- * Opcodes
    pattern OP_EXTENDED,
    pattern OP_CHUNK_END,
    pattern OP_TOOL_CALL_START,
    pattern OP_TOOL_CALL_END,
    pattern OP_THINK_START,
    pattern OP_THINK_END,
    pattern OP_CODE_BLOCK_START,
    pattern OP_CODE_BLOCK_END,
    pattern OP_FLUSH,
    pattern OP_STREAM_END,
    pattern OP_ERROR,

    -- * Envelopes
    pattern OP_ENVELOPE,

    -- * Constants
    maxHotId,

    -- * Byte classification
    isHotByte,
    isExtendedByte,
    isControlByte,
) where

import Data.Bits ((.&.))
import Data.ByteString (ByteString)
import Data.Word (Word32, Word8)

-- ════════════════════════════════════════════════════════════════════════════════
-- Token Types
-- ════════════════════════════════════════════════════════════════════════════════

-- | Token ID in the model's vocabulary (typically 0-150k)
type TokenId = Word32

-- | Hot token index (0-126)
type HotId = Word8

-- ════════════════════════════════════════════════════════════════════════════════
-- Frame Types
-- ════════════════════════════════════════════════════════════════════════════════

-- | A completed frame ready for transmission
newtype Frame = Frame {frameBytes :: ByteString}
    deriving newtype (Eq, Show, Semigroup, Monoid)

-- | Frame opcode byte
newtype FrameOp = FrameOp {unFrameOp :: Word8}
    deriving newtype (Eq, Show)

-- | Maximum hot token ID (0x7E = 126, 0x7F reserved)
maxHotId :: Word8
maxHotId = 126

-- ════════════════════════════════════════════════════════════════════════════════
-- Opcodes
-- ════════════════════════════════════════════════════════════════════════════════

-- | Extended token escape byte
pattern OP_EXTENDED :: FrameOp
pattern OP_EXTENDED = FrameOp 0x80

-- | Stream control opcodes (0xC0-0xCF)
pattern OP_CHUNK_END :: FrameOp
pattern OP_CHUNK_END = FrameOp 0xC0

pattern OP_TOOL_CALL_START :: FrameOp
pattern OP_TOOL_CALL_START = FrameOp 0xC1

pattern OP_TOOL_CALL_END :: FrameOp
pattern OP_TOOL_CALL_END = FrameOp 0xC2

pattern OP_THINK_START :: FrameOp
pattern OP_THINK_START = FrameOp 0xC3

pattern OP_THINK_END :: FrameOp
pattern OP_THINK_END = FrameOp 0xC4

pattern OP_CODE_BLOCK_START :: FrameOp
pattern OP_CODE_BLOCK_START = FrameOp 0xC5

pattern OP_CODE_BLOCK_END :: FrameOp
pattern OP_CODE_BLOCK_END = FrameOp 0xC6

pattern OP_FLUSH :: FrameOp
pattern OP_FLUSH = FrameOp 0xC7

pattern OP_STREAM_END :: FrameOp
pattern OP_STREAM_END = FrameOp 0xCF

pattern OP_ERROR :: FrameOp
pattern OP_ERROR = FrameOp 0xCE

-- | Envelope (0xF0) - Starts a signed envelope sequence
pattern OP_ENVELOPE :: FrameOp
pattern OP_ENVELOPE = FrameOp 0xF0

-- ════════════════════════════════════════════════════════════════════════════════
-- Byte Classification
-- ════════════════════════════════════════════════════════════════════════════════

-- | Is this byte a hot token? (high bit clear, not 0x7F)
isHotByte :: Word8 -> Bool
isHotByte byte = byte .&. 0x80 == 0 && byte /= 0x7F
{-# INLINE isHotByte #-}

-- | Is this byte an extended token escape?
isExtendedByte :: Word8 -> Bool
isExtendedByte byte = byte .&. 0xC0 == 0x80
{-# INLINE isExtendedByte #-}

-- | Is this byte a control frame?
isControlByte :: Word8 -> Bool
isControlByte byte = (byte .&. 0xF0 == 0xC0) || (byte == 0xF0)
{-# INLINE isControlByte #-}
