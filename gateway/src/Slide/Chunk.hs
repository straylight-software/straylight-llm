{-# LANGUAGE PatternSynonyms #-}

{- | Semantic chunking state machine

Processes tokens through state machine, emits SIGIL frames at semantic
boundaries. Handles special sequences like <think>, <tool_call>, and ```.
-}
module Slide.Chunk (
    -- * State machine
    ChunkState (..),
    ParseState (..),
    initChunkState,
    initChunkStateFromModel,

    -- * Processing
    processToken,
    ProcessResult (..),

    -- * Finalization
    finalizeChunk,
    flushTextChunk,
) where

import Data.Maybe (fromMaybe)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word32)

import Slide.HotTable (HotTable, lookupHot)
import Slide.Model (Model (..), SemanticDelimiters (..))
import Slide.Wire.Frame (
    Frame,
    FrameBuilder,
    FrameOp,
    finishFrame,
    resetBuilder,
    builderLength,
    writeChunkEnd,
    writeFlush,
    writeControl,
    writeExtendedToken,
    writeHotToken,
    writeStreamEnd,
    pattern OP_CODE_BLOCK_END,
    pattern OP_CODE_BLOCK_START,
    pattern OP_THINK_END,
    pattern OP_THINK_START,
    pattern OP_TOOL_CALL_END,
    pattern OP_TOOL_CALL_START,
 )

-- ════════════════════════════════════════════════════════════════════════════════
-- Types
-- ════════════════════════════════════════════════════════════════════════════════

-- | Parser state for semantic blocks
data ParseState
    = -- | Normal text output
      StateText
    | -- | Inside <think>...</think>
      StateThinking
    | -- | Inside <tool_call>...</tool_call>
      StateToolCall
    | -- | Inside ```...```
      StateCodeBlock
    deriving stock (Show, Eq)

-- | Full chunk state machine
data ChunkState = ChunkState
    { chunkParseState :: !ParseState
    , chunkFrameBuilder :: !FrameBuilder
    , chunkHotTable :: !HotTable
    , chunkBoundaryTokens :: !(VU.Vector Bool)
    , -- Special token IDs (pre-computed from tokenizer)
      chunkThinkStartToken :: !Word32
    , chunkThinkEndToken :: !Word32
    , chunkToolStartToken :: !Word32
    , chunkToolEndToken :: !Word32
    , chunkCodeFenceToken :: !Word32
    , chunkTokenCount :: !Int
    , chunkFlushThreshold :: !Int
    }

-- | Result of processing a token
data ProcessResult
    = -- | Keep accumulating
      ResultContinue
    | -- | Emit frame (chunk boundary reached)
      ResultEmitChunk !Frame
    | -- | State transition occurred
      ResultStateChange !FrameOp
    deriving stock (Show)

-- ════════════════════════════════════════════════════════════════════════════════
-- Initialization
-- ════════════════════════════════════════════════════════════════════════════════

-- | Initialize state machine
initChunkState ::
    FrameBuilder ->
    HotTable ->
    -- | Boundary tokens (newline, semicolon, etc.)
    VU.Vector Bool ->
    -- | (think_start, think_end) token IDs
    (Word32, Word32) ->
    -- | (tool_call_start, tool_call_end) token IDs
    (Word32, Word32) ->
    -- | Code fence (```) token ID
    Word32 ->
    -- | Flush threshold (tokens)
    Int ->
    ChunkState
initChunkState frameBuilder hotTable boundaries (thinkStart, thinkEnd) (toolStart, toolEnd) codeFence flushThreshold =
    ChunkState
        { chunkParseState = StateText
        , chunkFrameBuilder = frameBuilder
        , chunkHotTable = hotTable
        , chunkBoundaryTokens = boundaries
        , chunkThinkStartToken = thinkStart
        , chunkThinkEndToken = thinkEnd
        , chunkToolStartToken = toolStart
        , chunkToolEndToken = toolEnd
        , chunkCodeFenceToken = codeFence
        , chunkTokenCount = 0
        , chunkFlushThreshold = flushThreshold
        }

{- | Initialize state machine from Model

Extracts all necessary configuration from the Model abstraction.
This is the preferred way to initialize ChunkState.
-}
initChunkStateFromModel :: FrameBuilder -> Model -> ChunkState
initChunkStateFromModel frameBuilder model =
    let delims = modelDelimiters model
        -- Use maxBound as sentinel for "no such token"
        -- This ensures comparisons will never match
        sentinel = maxBound :: Word32
     in ChunkState
            { chunkParseState = StateText
            , chunkFrameBuilder = frameBuilder
            , chunkHotTable = modelHotTable model
            , chunkBoundaryTokens = modelBoundaries model
            , chunkThinkStartToken = fromMaybe sentinel (delimThinkStartToken delims)
            , chunkThinkEndToken = fromMaybe sentinel (delimThinkEndToken delims)
            , chunkToolStartToken = fromMaybe sentinel (delimToolCallStartToken delims)
            , chunkToolEndToken = fromMaybe sentinel (delimToolCallEndToken delims)
            , chunkCodeFenceToken = fromMaybe sentinel (delimCodeFenceToken delims)
            , chunkTokenCount = 0
            , chunkFlushThreshold = 32 -- Default for model-based init (can be overridden?)
            }

-- ════════════════════════════════════════════════════════════════════════════════
-- Processing
-- ════════════════════════════════════════════════════════════════════════════════

-- | Process single token through state machine
processToken :: ChunkState -> Word32 -> IO (ChunkState, ProcessResult)
processToken state tokenId = do
    -- Check for state transitions first
    let (newParseState, maybeControlOp) = checkStateTransition state tokenId
        -- Reset token count on state change (new semantic block)
        newCount = if newParseState /= chunkParseState state then 0 else chunkTokenCount state + 1
        updatedState = state{chunkParseState = newParseState, chunkTokenCount = newCount}

    -- Emit control frame if state changed
    case maybeControlOp of
        Just controlOp -> do
            writeControl (chunkFrameBuilder updatedState) controlOp
            pure (updatedState, ResultStateChange controlOp)
        Nothing -> do
            -- Encode token using hot table
            case lookupHot (chunkHotTable updatedState) tokenId of
                Just hotId -> writeHotToken (chunkFrameBuilder updatedState) hotId
                Nothing -> writeExtendedToken (chunkFrameBuilder updatedState) tokenId

            -- Check for chunk boundary conditions
            let isTextBoundary = chunkParseState updatedState == StateText && isBoundaryToken updatedState tokenId
            let isSizeBoundary = chunkTokenCount updatedState >= chunkFlushThreshold updatedState

            if isTextBoundary
                then do
                    writeChunkEnd (chunkFrameBuilder updatedState)
                    completedFrame <- finishFrame (chunkFrameBuilder updatedState)
                    resetBuilder (chunkFrameBuilder updatedState)
                    pure (updatedState{chunkTokenCount = 0}, ResultEmitChunk completedFrame)
                else if isSizeBoundary
                    then do
                        writeFlush (chunkFrameBuilder updatedState)
                        completedFrame <- finishFrame (chunkFrameBuilder updatedState)
                        resetBuilder (chunkFrameBuilder updatedState)
                        pure (updatedState{chunkTokenCount = 0}, ResultEmitChunk completedFrame)
                    else
                        pure (updatedState, ResultContinue)

-- | Check for state transitions based on special tokens
checkStateTransition :: ChunkState -> Word32 -> (ParseState, Maybe FrameOp)
checkStateTransition state tokenId = case chunkParseState state of
    StateText
        | tokenId == chunkThinkStartToken state -> (StateThinking, Just OP_THINK_START)
        | tokenId == chunkToolStartToken state -> (StateToolCall, Just OP_TOOL_CALL_START)
        | tokenId == chunkCodeFenceToken state -> (StateCodeBlock, Just OP_CODE_BLOCK_START)
        | otherwise -> (StateText, Nothing)
    StateThinking
        | tokenId == chunkThinkEndToken state -> (StateText, Just OP_THINK_END)
        | otherwise -> (StateThinking, Nothing)
    StateToolCall
        | tokenId == chunkToolEndToken state -> (StateText, Just OP_TOOL_CALL_END)
        | otherwise -> (StateToolCall, Nothing)
    StateCodeBlock
        | tokenId == chunkCodeFenceToken state -> (StateText, Just OP_CODE_BLOCK_END)
        | otherwise -> (StateCodeBlock, Nothing)

-- | Check if token is a chunk boundary
isBoundaryToken :: ChunkState -> Word32 -> Bool
isBoundaryToken state tokenId
    | tokenId >= fromIntegral (VU.length (chunkBoundaryTokens state)) = False
    | otherwise = chunkBoundaryTokens state VU.! fromIntegral tokenId
{-# INLINE isBoundaryToken #-}

-- ════════════════════════════════════════════════════════════════════════════════
-- Finalization
-- ════════════════════════════════════════════════════════════════════════════════

-- | Finalize stream: close any open blocks and emit STREAM_END
finalizeChunk :: ChunkState -> IO Frame
finalizeChunk state = do
    -- Close any open semantic blocks
    case chunkParseState state of
        StateThinking -> writeControl (chunkFrameBuilder state) OP_THINK_END
        StateToolCall -> writeControl (chunkFrameBuilder state) OP_TOOL_CALL_END
        StateCodeBlock -> writeControl (chunkFrameBuilder state) OP_CODE_BLOCK_END
        StateText -> pure ()

    writeStreamEnd (chunkFrameBuilder state)
    finishFrame (chunkFrameBuilder state)

-- | Flush current text chunk if any
flushTextChunk :: ChunkState -> IO (Maybe Frame)
flushTextChunk state = do
    len <- builderLength (chunkFrameBuilder state)
    if len > 0 && chunkParseState state == StateText
        then do
            writeChunkEnd (chunkFrameBuilder state)
            frame <- finishFrame (chunkFrameBuilder state)
            resetBuilder (chunkFrameBuilder state)
            pure $ Just frame
        else pure Nothing
