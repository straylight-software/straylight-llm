{-# LANGUAGE PatternSynonyms #-}

{- | Frame building for SIGIL wire format

Pre-allocates pinned buffers for zero-copy emission on the hot path.
NOT thread-safe — use one builder per stream.
-}
module Slide.Wire.Frame (
    -- * Re-exports from Types
    Frame (..),
    FrameOp (..),
    TokenId,
    HotId,
    maxHotId,
    isHotByte,
    isExtendedByte,
    isControlByte,

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

    -- * Frame building
    FrameBuilder,
    newFrameBuilder,
    resetBuilder,
    builderLength,
    finishFrame,
    unsafeFinishFrame,

    -- * Writing operations
    writeHotToken,
    writeExtendedToken,
    writeControl,
    writeChunkEnd,
    writeFlush,
    writeStreamEnd,
    writeBytes,
) where

import Control.Exception (throwIO)
import Control.Monad (when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Internal qualified as BSI
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Word (Word8)
import Foreign.ForeignPtr (ForeignPtr, castForeignPtr, withForeignPtr)
import Foreign.Marshal.Utils (copyBytes)
import Foreign.Ptr (Ptr, castPtr, plusPtr)
import Foreign.Storable (pokeByteOff)

import Slide.Wire.Types (
    Frame (..),
    FrameOp (..),
    HotId,
    TokenId,
    isControlByte,
    isExtendedByte,
    isHotByte,
    maxHotId,
    pattern OP_CHUNK_END,
    pattern OP_CODE_BLOCK_END,
    pattern OP_CODE_BLOCK_START,
    pattern OP_ERROR,
    pattern OP_EXTENDED,
    pattern OP_FLUSH,
    pattern OP_STREAM_END,
    pattern OP_THINK_END,
    pattern OP_THINK_START,
    pattern OP_TOOL_CALL_END,
    pattern OP_TOOL_CALL_START,
 )
import Slide.Wire.Varint (pokeVarint, varintSize)

-- ════════════════════════════════════════════════════════════════════════════════
-- Frame Builder
-- ════════════════════════════════════════════════════════════════════════════════

{- | Mutable frame builder for hot path

Pre-allocates a pinned buffer and writes directly to avoid allocations.
-}
data FrameBuilder = FrameBuilder
    { builderBuffer :: !(ForeignPtr Word8)
    -- ^ Pinned buffer
    , builderCapacity :: !Int
    -- ^ Maximum capacity in bytes
    , builderOffset :: !(IORef Int)
    -- ^ Current write position
    }

-- | Create new builder with given capacity
newFrameBuilder :: Int -> IO FrameBuilder
newFrameBuilder capacity = do
    bufferPointer <- BSI.mallocByteString capacity
    offsetRef <- newIORef 0
    pure
        FrameBuilder
            { builderBuffer = bufferPointer
            , builderCapacity = capacity
            , builderOffset = offsetRef
            }

-- | Reset builder for reuse (zero-cost, just resets offset)
resetBuilder :: FrameBuilder -> IO ()
resetBuilder builder = writeIORef (builderOffset builder) 0
{-# INLINE resetBuilder #-}

-- | Current length of builder content
builderLength :: FrameBuilder -> IO Int
builderLength builder = readIORef (builderOffset builder)
{-# INLINE builderLength #-}

-- | Extract completed frame (copies bytes)
finishFrame :: FrameBuilder -> IO Frame
finishFrame builder = do
    currentLength <- readIORef (builderOffset builder)
    Frame
        <$> withForeignPtr
            (builderBuffer builder)
            ( \bufferPtr ->
                BS.packCStringLen (castPtr bufferPtr, currentLength)
            )

-- | Extract frame without copying (unsafe if builder is reused!)
unsafeFinishFrame :: FrameBuilder -> IO Frame
unsafeFinishFrame builder = do
    currentLength <- readIORef (builderOffset builder)
    pure $ Frame $ BSI.fromForeignPtr (castForeignPtr $ builderBuffer builder) 0 currentLength

-- ════════════════════════════════════════════════════════════════════════════════
-- Writing Operations
-- ════════════════════════════════════════════════════════════════════════════════

-- | Write a hot token (single byte, 0x00-0x7E)
writeHotToken :: FrameBuilder -> HotId -> IO ()
writeHotToken builder hotTokenId = do
    currentOffset <- readIORef (builderOffset builder)
    when (currentOffset >= builderCapacity builder) $
        throwIO $ userError "[slide] [frame] [error] FrameBuilder overflow"
    when (hotTokenId > maxHotId) $
        throwIO $ userError $
            "[slide] [frame] [error] Invalid hot ID: " <> show hotTokenId
    withForeignPtr (builderBuffer builder) $ \bufferPtr ->
        pokeByteOff bufferPtr currentOffset hotTokenId
    writeIORef (builderOffset builder) (currentOffset + 1)
{-# INLINE writeHotToken #-}

-- | Write an extended token (0x80 escape + varint)
writeExtendedToken :: FrameBuilder -> TokenId -> IO ()
writeExtendedToken builder tokenId = do
    currentOffset <- readIORef (builderOffset builder)
    let bytesNeeded = 1 + varintSize tokenId
    when (currentOffset + bytesNeeded > builderCapacity builder) $
        throwIO $ userError "[slide] [frame] [error] FrameBuilder overflow"
    withForeignPtr (builderBuffer builder) $ \bufferPtr -> do
        pokeByteOff bufferPtr currentOffset (0x80 :: Word8)
        bytesWritten <- pokeVarint (bufferPtr `plusPtr` (currentOffset + 1)) tokenId
        writeIORef (builderOffset builder) (currentOffset + 1 + bytesWritten)
{-# INLINE writeExtendedToken #-}

-- | Write a control opcode
writeControl :: FrameBuilder -> FrameOp -> IO ()
writeControl builder (FrameOp opcode) = do
    currentOffset <- readIORef (builderOffset builder)
    when (currentOffset >= builderCapacity builder) $
        throwIO $ userError "[slide] [frame] [error] FrameBuilder overflow"
    withForeignPtr (builderBuffer builder) $ \bufferPtr ->
        pokeByteOff bufferPtr currentOffset opcode
    writeIORef (builderOffset builder) (currentOffset + 1)
{-# INLINE writeControl #-}

-- | Convenience: write CHUNK_END
writeChunkEnd :: FrameBuilder -> IO ()
writeChunkEnd builder = writeControl builder OP_CHUNK_END
{-# INLINE writeChunkEnd #-}

-- | Convenience: write FLUSH
writeFlush :: FrameBuilder -> IO ()
writeFlush builder = writeControl builder OP_FLUSH
{-# INLINE writeFlush #-}

-- | Convenience: write STREAM_END
writeStreamEnd :: FrameBuilder -> IO ()
writeStreamEnd builder = writeControl builder OP_STREAM_END
{-# INLINE writeStreamEnd #-}

-- | Write raw bytes (for bulk operations)
writeBytes :: FrameBuilder -> ByteString -> IO ()
writeBytes builder inputBytes = do
    currentOffset <- readIORef (builderOffset builder)
    let inputLength = BS.length inputBytes
    when (currentOffset + inputLength > builderCapacity builder) $
        throwIO $ userError "[slide] [frame] [error] FrameBuilder overflow"
    withForeignPtr (builderBuffer builder) $ \bufferPtr ->
        BS.useAsCStringLen inputBytes $ \(sourcePtr, sourceLength) ->
            copyBytes (bufferPtr `plusPtr` currentOffset) (castPtr sourcePtr :: Ptr Word8) sourceLength
    writeIORef (builderOffset builder) (currentOffset + inputLength)
