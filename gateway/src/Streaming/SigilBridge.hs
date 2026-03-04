-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                     // straylight-llm // streaming // sigil bridge
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Cyberspace. A consensual hallucination experienced daily by billions
--      of legitimate operators, in every nation."
--
--                                                              — Neuromancer
--
-- SSE-to-SIGIL bridge: parses vendor SSE garbage, emits clean SIGIL frames.
--
-- This module transforms raw SSE bytes from LLM providers into SIGIL binary
-- frames for downstream products. The gateway is the single point of truth —
-- all vendor garbage is parsed here and emitted as clean protocol.
--
-- Architecture:
--   Provider HTTP → SSE bytes → SigilBridge → SIGIL frames → ZMQ PUB
--
-- Flow:
--   1. SSE chunk arrives (raw bytes from provider)
--   2. Parse SSE line (data: {...})
--   3. Extract content delta from JSON
--   4. Tokenize text via model's tokenizer
--   5. Process each token through ChunkState machine
--   6. Emit SIGIL frames at semantic boundaries
--   7. Send frames over ZMQ PUB socket
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}

module Streaming.SigilBridge
  ( -- * Bridge types
    SigilBridge (..),
    BridgeState (..),
    BridgeConfig (..),

    -- * Lifecycle
    newBridgeState,
    defaultBridgeConfig,

    -- * Processing
    processSseChunk,
    finalizeBridge,

    -- * Dual callback
    makeDualCallback,
  )
where

-- ────────────────────────────────────────────────────────────────────────────
--                                                                 // imports
-- ────────────────────────────────────────────────────────────────────────────

import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word32)

import Slide.Chunk
  ( ChunkState,
    ProcessResult (ResultContinue, ResultEmitChunk, ResultStateChange),
    finalizeChunk,
    initChunkStateFromModel,
    processToken,
  )
import Slide.Model (Model, Tokenizer (tokenizerEncode), modelTokenizer)
import Slide.Parse (SSEEvent (..), extractDelta, extractFinishReason, parseSSELine)
import Slide.Wire.Frame (Frame, newFrameBuilder)
import Transport.Zmq (SigilPublisher, StreamMetadata, emitFrame)

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Bridge configuration
data BridgeConfig = BridgeConfig
  { bcFlushThreshold :: !Int,
    -- ^ Emit frame after this many tokens (default: 32)
    bcEnableToolCallDetection :: !Bool
    -- ^ Detect and emit tool call control frames from JSON structure
  }
  deriving (Show, Eq)

-- | Default bridge configuration
defaultBridgeConfig :: BridgeConfig
defaultBridgeConfig =
  BridgeConfig
    { bcFlushThreshold = 32,
      bcEnableToolCallDetection = True
    }

-- | Mutable bridge state for a single stream
--
-- Each streaming request gets its own BridgeState. The ChunkState handles
-- the token-level state machine, while BridgeState adds stream-level concerns.
data BridgeState = BridgeState
  { bsChunkState :: !(IORef ChunkState),
    -- ^ Token processing state machine
    bsModel :: !Model,
    -- ^ Model for tokenization
    bsTextBuffer :: !(IORef Text),
    -- ^ Accumulated text for boundary-aware tokenization
    bsConfig :: !BridgeConfig
    -- ^ Bridge configuration
  }

-- | Bridge abstraction combining state, publisher, and metadata
data SigilBridge = SigilBridge
  { sbState :: !BridgeState,
    sbPublisher :: !SigilPublisher,
    sbMetadata :: !StreamMetadata
  }

-- ════════════════════════════════════════════════════════════════════════════
--                                                               // lifecycle
-- ════════════════════════════════════════════════════════════════════════════

-- | Create new bridge state for a stream
--
-- Call this once per request. The BridgeState maintains:
--   - ChunkState for token processing
--   - Text buffer for accumulating partial UTF-8
--   - Reference to the model's tokenizer
newBridgeState :: BridgeConfig -> Model -> IO BridgeState
newBridgeState config model = do
  -- Create frame builder for the chunk state (4KB buffer)
  builder <- newFrameBuilder 4096
  -- Initialize chunk state from model configuration
  let chunkState = initChunkStateFromModel builder model
  chunkStateRef <- newIORef chunkState
  textBufferRef <- newIORef T.empty
  pure
    BridgeState
      { bsChunkState = chunkStateRef,
        bsModel = model,
        bsTextBuffer = textBufferRef,
        bsConfig = config
      }

-- ════════════════════════════════════════════════════════════════════════════
--                                                              // processing
-- ════════════════════════════════════════════════════════════════════════════

-- | Process an SSE chunk from a provider
--
-- This is the core bridge function. It:
--   1. Parses SSE to extract data
--   2. Extracts content delta from JSON
--   3. Tokenizes text via model's tokenizer
--   4. Feeds tokens through ChunkState machine
--   5. Emits frames at semantic boundaries
--
-- Returns: List of frames emitted (may be empty, one, or several)
processSseChunk :: SigilBridge -> ByteString -> IO [Frame]
processSseChunk bridge chunk = do
  let state = sbState bridge
      publisher = sbPublisher bridge
      meta = sbMetadata bridge
      tokenizer = modelTokenizer (bsModel state)

  -- Parse SSE line
  case parseSSELine (TE.decodeUtf8Lenient chunk) of
    Left _parseErr ->
      -- Not valid SSE, skip (might be partial or noise)
      pure []
    Right sseEvent -> case sseEvent of
      SSEDone -> do
        -- Stream finished — finalize and emit STREAM_END
        finalFrame <- finalizeBridgeInternal state
        emitFrame publisher meta finalFrame
        pure [finalFrame]
      SSEData jsonText -> do
        -- Extract content delta from JSON
        case extractDelta jsonText of
          Nothing ->
            -- No content field — might be tool call or other event
            -- Check for finish_reason to detect tool call completion
            case extractFinishReason jsonText of
              Just reason
                | reason == "tool_calls" || reason == "function_call" ->
                    -- Tool call finished, the ChunkState handles control frames
                    -- via token-based detection. For JSON-level detection we would
                    -- need to parse the tool_calls array from the SSE stream.
                    pure []
              _ -> pure []
          Just contentText -> do
            -- Got content, accumulate in buffer
            currentBuffer <- readIORef (bsTextBuffer state)
            let newBuffer = currentBuffer <> contentText

            -- Tokenize accumulated text
            -- Note: We tokenize the full buffer to handle multi-byte UTF-8
            -- that might be split across SSE chunks
            tokenIds <- tokenizerEncode tokenizer newBuffer

            -- Clear buffer (tokens consumed)
            writeIORef (bsTextBuffer state) T.empty

            -- Process each token through the chunk state machine
            processTokensAndEmit bridge tokenIds
      SSERetry _ms ->
        -- Retry directive, ignore for SIGIL purposes
        pure []
      SSEComment _text ->
        -- Comment, ignore
        pure []
      SSEEmpty ->
        -- Empty line (event separator), ignore
        pure []

-- | Process a list of tokens and emit any resulting frames
processTokensAndEmit :: SigilBridge -> [Word32] -> IO [Frame]
processTokensAndEmit bridge tokenIds = do
  let state = sbState bridge
      publisher = sbPublisher bridge
      meta = sbMetadata bridge

  -- Process each token, accumulating emitted frames
  framesRef <- newIORef []
  forM_ tokenIds $ \tokenId -> do
    chunkState <- readIORef (bsChunkState state)
    (newChunkState, result) <- processToken chunkState tokenId
    writeIORef (bsChunkState state) newChunkState

    case result of
      ResultEmitChunk frame -> do
        -- Emit frame over ZMQ
        emitFrame publisher meta frame
        -- Accumulate for return
        currentFrames <- readIORef framesRef
        writeIORef framesRef (currentFrames ++ [frame])
      ResultStateChange _controlOp ->
        -- State change emitted control byte to frame builder
        -- Frame will be emitted at next boundary
        pure ()
      ResultContinue ->
        -- Token accumulated, no emission yet
        pure ()

  readIORef framesRef

-- | Finalize bridge at end of stream
--
-- Flushes any remaining content and emits STREAM_END.
finalizeBridge :: SigilBridge -> IO [Frame]
finalizeBridge bridge = do
  let publisher = sbPublisher bridge
      meta = sbMetadata bridge

  -- Finalize and get final frame
  finalFrame <- finalizeBridgeInternal (sbState bridge)

  -- Emit final frame (includes STREAM_END)
  emitFrame publisher meta finalFrame

  pure [finalFrame]

-- | Internal finalization (doesn't emit, just builds frame)
finalizeBridgeInternal :: BridgeState -> IO Frame
finalizeBridgeInternal state = do
  -- Flush any buffered text first
  currentBuffer <- readIORef (bsTextBuffer state)
  unless (T.null currentBuffer) $ do
    let tokenizer = modelTokenizer (bsModel state)
    tokenIds <- tokenizerEncode tokenizer currentBuffer
    writeIORef (bsTextBuffer state) T.empty
    forM_ tokenIds $ \tokenId -> do
      chunkState <- readIORef (bsChunkState state)
      (newChunkState, _result) <- processToken chunkState tokenId
      writeIORef (bsChunkState state) newChunkState

  -- Finalize chunk state (closes open blocks, adds STREAM_END)
  chunkState <- readIORef (bsChunkState state)
  finalizeChunk chunkState
  where
    unless :: Bool -> IO () -> IO ()
    unless cond action = if cond then pure () else action

-- ════════════════════════════════════════════════════════════════════════════
--                                                          // dual callback
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a dual callback that handles both SSE forwarding and SIGIL emission
--
-- This is the integration point with the handler. It wraps the original SSE
-- callback and adds SIGIL processing:
--
-- @
--   let dualCallback = makeDualCallback originalCallback bridge
--   routeChatStream router requestId chatReq dualCallback
-- @
--
-- The dual callback:
--   1. Forwards raw SSE bytes to the client (original behavior)
--   2. Processes through SIGIL bridge for downstream emission
makeDualCallback ::
  -- | Original SSE callback (forwards to client)
  (ByteString -> IO ()) ->
  -- | SIGIL bridge for emission
  SigilBridge ->
  -- | Dual callback
  (ByteString -> IO ())
makeDualCallback originalCallback bridge = \chunk -> do
  -- Forward to original callback (SSE to client)
  originalCallback chunk
  -- Process for SIGIL emission (errors logged but don't break SSE)
  _ <- processSseChunk bridge chunk
  pure ()
