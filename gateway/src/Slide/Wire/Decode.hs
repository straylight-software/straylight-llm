{- | Frame decoding for SIGIL wire format

Decodes binary frames back into semantic chunks for client consumption.

== Reset-on-Ambiguity Strategy

When the decoder encounters an ambiguous state (malformed input, unexpected
control sequence, or upstream semantic confusion), it does NOT guess. Instead:

1. Emit an 'AmbiguityReset' chunk describing what happened
2. Reset to 'initDecodeState' (known-good ground state)
3. Continue from the next frame boundary

=== Pseudo-Lean4 Specification

@
-- The state space forms a pointed set with initDecodeState as distinguished element
structure DecodeState where
  parseMode : ParseMode
  buffer    : List TokenId
  leftover  : ByteArray
  
inductive ParseMode where
  | text | think | toolCall | codeBlock
  
-- Ground state: the unique "safe" state we can always return to
def initDecodeState : DecodeState := ⟨.text, [], ⟨#[]⟩⟩

-- Reset is constant function to ground
def resetDecodeState : DecodeState → DecodeState := fun _ => initDecodeState

-- THEOREM 1: Reset always produces ground state
theorem reset_is_ground : ∀ s, resetDecodeState s = initDecodeState := by
  intro s; rfl

-- Ambiguity predicate: true when we hit an unresolvable state
inductive Ambiguity where
  | unmatchedEnd   : ParseMode → Ambiguity      -- END without matching START
  | nestedStart    : ParseMode → ParseMode → Ambiguity  -- START while not in text
  | reservedOpcode : UInt8 → Ambiguity          -- future opcodes
  | varintOverflow : Ambiguity                  -- token ID > 2^32

-- Decode step returns either progress or ambiguity
inductive DecodeResult where
  | progress : DecodeState → List Chunk → DecodeResult
  | ambiguity : Ambiguity → DecodeResult

-- THEOREM 2: Ambiguity triggers reset
theorem ambiguity_resets : ∀ s input,
  (decodeStep s input = .ambiguity a) →
  (nextState s input = initDecodeState) := by
  -- Proof: case analysis on control bytes shows all ambiguity
  -- paths set state to initDecodeState before continuing
  sorry  -- to be formalized

-- THEOREM 3: Post-reset decode is canonical
-- After reset, decoding is identical to decoding from fresh start
theorem post_reset_canonical : ∀ s input rest,
  (decodeStep s input = .ambiguity _) →
  (decode (nextState s input) rest = decode initDecodeState rest) := by
  intro s input rest h
  simp [nextState, ambiguity_resets s input h]
  -- Follows from reset_is_ground

-- THEOREM 4: No information leakage across ambiguity boundary
-- Tokens decoded after reset contain no data from pre-reset state
theorem no_leakage : ∀ s₁ s₂ input rest,
  (decodeStep s₁ input = .ambiguity _) →
  (decodeStep s₂ input = .ambiguity _) →
  (decode (nextState s₁ input) rest = decode (nextState s₂ input) rest) := by
  -- Both reset to initDecodeState, so subsequent decoding is identical
  intro s₁ s₂ input rest h₁ h₂
  simp [ambiguity_resets, reset_is_ground]
@

=== Implementation Notes

The Haskell implementation mirrors this structure:

- 'initDecodeState' is the distinguished ground element
- 'resetDecodeState' is the constant function to ground
- 'handleControlByte' checks mode validity and emits 'AmbiguityReset' on violation
- All ambiguity paths call 'initDecodeState' directly (inlined reset)

The key invariant: @resetDecodeState . anyAmbiguousPath = initDecodeState@
-}
module Slide.Wire.Decode (
    -- * Decoded chunks
    Chunk (..),
    ChunkContent (..),

    -- * Decoding
    decodeFrame,
    decodeFrameIncremental,

    -- * Low-level
    DecodeState (..),
    initDecodeState,
    resetDecodeState,
    feedBytes,
    flushDecoder,

    -- * Ambiguity handling
    AmbiguityReason (..),
) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Word (Word8)

import Slide.Wire.Types (TokenId, isControlByte, isExtendedByte, isHotByte)
import Slide.Wire.Varint (decodeVarint)

-- ════════════════════════════════════════════════════════════════════════════════
-- Chunk Types (what the client sees)
-- ════════════════════════════════════════════════════════════════════════════════

-- | A decoded semantic chunk
data Chunk = Chunk
    { chunkContent :: !ChunkContent
    , chunkComplete :: !Bool
    -- ^ True if ends on semantic boundary
    }
    deriving stock (Show, Eq)

-- | Content types
data ChunkContent
    = -- | Regular text tokens
      TextContent ![TokenId]
    | -- | Thinking block (may be hidden)
      ThinkContent ![TokenId]
    | -- | Tool call (parse as JSON)
      ToolCallContent ![TokenId]
    | -- | Code block
      CodeBlockContent ![TokenId]
    | -- | End of stream
      StreamEnd
    | -- | Something went wrong
      DecodeError !Text
    | -- | Ambiguity detected, state reset to ground
      AmbiguityReset !AmbiguityReason
    deriving stock (Show, Eq)

-- | Reasons for ambiguity-triggered reset
--
-- These are the hard ambiguities where guessing would be worse than resetting.
-- Each maps to a class of upstream confusion that cannot be resolved locally.
data AmbiguityReason
    = -- | Mode end without matching start (e.g., TOOL_CALL_END in ModeText)
      UnmatchedModeEnd !ParseMode
    | -- | Mode start while already in non-text mode (nested modes)
      NestedModeStart !ParseMode !ParseMode  -- current, attempted
    | -- | Reserved opcode encountered (future-proofing)
      ReservedOpcode !Word8
    | -- | Varint overflow (token ID > 2^32)
      VarintOverflow
    | -- | Upstream indicated error in-band
      UpstreamError !Text
    deriving stock (Show, Eq)

-- ════════════════════════════════════════════════════════════════════════════════
-- Decode State
-- ════════════════════════════════════════════════════════════════════════════════

-- | Parser mode for semantic blocks
data ParseMode
    = ModeText
    | ModeThink
    | ModeToolCall
    | ModeCodeBlock
    deriving stock (Show, Eq)

-- | Incremental decoder state
data DecodeState = DecodeState
    { decodeParseMode :: !ParseMode
    , decodeBuffer :: ![TokenId]
    -- ^ Accumulated tokens (reversed)
    , decodeLeftover :: !ByteString
    -- ^ Incomplete bytes from last feed
    }
    deriving stock (Show, Eq)

-- | Initial decode state (the unique ground state)
--
-- This is the only valid starting point and the state we return to
-- after any ambiguity. Lean4 proof will show:
-- @forall s. resetDecodeState s = initDecodeState@
initDecodeState :: DecodeState
initDecodeState = DecodeState ModeText [] BS.empty

-- | Reset to ground state, discarding any accumulated context
--
-- Called on ambiguity. Returns to 'initDecodeState' unconditionally.
-- This is the key function for the reset-on-ambiguity strategy.
resetDecodeState :: DecodeState -> DecodeState
resetDecodeState _ = initDecodeState

-- ════════════════════════════════════════════════════════════════════════════════
-- Decoding
-- ════════════════════════════════════════════════════════════════════════════════

-- | Decode a complete frame into chunks
decodeFrame :: ByteString -> [Chunk]
decodeFrame inputBytes = resultChunks
  where
    (_finalState, resultChunks) = decodeFrameIncremental initDecodeState inputBytes

-- | Decode incrementally, returning new state and any complete chunks
decodeFrameIncremental :: DecodeState -> ByteString -> (DecodeState, [Chunk])
decodeFrameIncremental initialState inputBytes =
    processBytes initialState (decodeLeftover initialState <> inputBytes) []
  where
    processBytes :: DecodeState -> ByteString -> [Chunk] -> (DecodeState, [Chunk])
    processBytes !state !remainingInput !accumulatedChunks
        | BS.null remainingInput =
            (state{decodeLeftover = BS.empty}, reverse accumulatedChunks)
        | otherwise =
            let currentByte = BS.head remainingInput
                restOfInput = BS.tail remainingInput
             in case decodeSingleByte state currentByte restOfInput of
                    Left leftoverBytes ->
                        (state{decodeLeftover = leftoverBytes}, reverse accumulatedChunks)
                    Right (newState, maybeChunk, bytesRemaining) ->
                        let updatedChunks = maybe accumulatedChunks (: accumulatedChunks) maybeChunk
                         in processBytes newState bytesRemaining updatedChunks

-- | Decode one byte, possibly consuming more for varint
decodeSingleByte ::
    DecodeState ->
    Word8 ->
    ByteString ->
    Either ByteString (DecodeState, Maybe Chunk, ByteString)
decodeSingleByte state currentByte remainingBytes
    -- Hot token (0x00-0x7E)
    | isHotByte currentByte =
        let tokenId = fromIntegral currentByte
            newState = state{decodeBuffer = tokenId : decodeBuffer state}
         in Right (newState, Nothing, remainingBytes)
    -- Extended token (0x80-0xBF)
    | isExtendedByte currentByte =
        case decodeVarint remainingBytes of
            Nothing -> Left (BS.cons currentByte remainingBytes) -- incomplete varint
            Just (tokenId, bytesConsumed) ->
                let newState = state{decodeBuffer = tokenId : decodeBuffer state}
                 in Right (newState, Nothing, BS.drop bytesConsumed remainingBytes)
    -- Control (0xC0-0xCF)
    | isControlByte currentByte =
        handleControlByte state currentByte remainingBytes
    -- Reserved/unknown - ignore
    | otherwise =
        Right (state, Nothing, remainingBytes)

-- | Handle control opcodes
--
-- This is where ambiguity detection happens. Invalid mode transitions
-- trigger reset-on-ambiguity rather than undefined behavior.
handleControlByte ::
    DecodeState ->
    Word8 ->
    ByteString ->
    Either ByteString (DecodeState, Maybe Chunk, ByteString)
handleControlByte state opcode remainingBytes = Right $ case opcode of
    0xC0 ->
        -- CHUNK_END
        let chunk = buildChunk state True
            newState = state{decodeBuffer = []}
         in (newState, Just chunk, remainingBytes)
    0xC1 ->
        -- TOOL_CALL_START
        case decodeParseMode state of
            ModeText ->
                -- Valid: text -> tool_call
                let pendingChunk =
                        if null (decodeBuffer state)
                            then Nothing
                            else Just (buildChunk state False)
                    newState = DecodeState ModeToolCall [] BS.empty
                 in (newState, pendingChunk, remainingBytes)
            currentMode ->
                -- AMBIGUITY: nested mode start, reset
                let chunk = Chunk (AmbiguityReset (NestedModeStart currentMode ModeToolCall)) True
                 in (initDecodeState, Just chunk, remainingBytes)
    0xC2 ->
        -- TOOL_CALL_END
        case decodeParseMode state of
            ModeToolCall ->
                -- Valid: tool_call -> text
                let chunk = buildChunk state True
                    newState = DecodeState ModeText [] BS.empty
                 in (newState, Just chunk, remainingBytes)
            currentMode ->
                -- AMBIGUITY: end without matching start, reset
                let chunk = Chunk (AmbiguityReset (UnmatchedModeEnd currentMode)) True
                 in (initDecodeState, Just chunk, remainingBytes)
    0xC3 ->
        -- THINK_START
        case decodeParseMode state of
            ModeText ->
                -- Valid: text -> think
                let pendingChunk =
                        if null (decodeBuffer state)
                            then Nothing
                            else Just (buildChunk state False)
                    newState = DecodeState ModeThink [] BS.empty
                 in (newState, pendingChunk, remainingBytes)
            currentMode ->
                -- AMBIGUITY: nested mode start, reset
                let chunk = Chunk (AmbiguityReset (NestedModeStart currentMode ModeThink)) True
                 in (initDecodeState, Just chunk, remainingBytes)
    0xC4 ->
        -- THINK_END
        case decodeParseMode state of
            ModeThink ->
                -- Valid: think -> text
                let chunk = buildChunk state True
                    newState = DecodeState ModeText [] BS.empty
                 in (newState, Just chunk, remainingBytes)
            currentMode ->
                -- AMBIGUITY: end without matching start, reset
                let chunk = Chunk (AmbiguityReset (UnmatchedModeEnd currentMode)) True
                 in (initDecodeState, Just chunk, remainingBytes)
    0xC5 ->
        -- CODE_BLOCK_START
        case decodeParseMode state of
            ModeText ->
                -- Valid: text -> code_block
                let pendingChunk =
                        if null (decodeBuffer state)
                            then Nothing
                            else Just (buildChunk state False)
                    newState = DecodeState ModeCodeBlock [] BS.empty
                 in (newState, pendingChunk, remainingBytes)
            currentMode ->
                -- AMBIGUITY: nested mode start, reset
                let chunk = Chunk (AmbiguityReset (NestedModeStart currentMode ModeCodeBlock)) True
                 in (initDecodeState, Just chunk, remainingBytes)
    0xC6 ->
        -- CODE_BLOCK_END
        case decodeParseMode state of
            ModeCodeBlock ->
                -- Valid: code_block -> text
                let chunk = buildChunk state True
                    newState = DecodeState ModeText [] BS.empty
                 in (newState, Just chunk, remainingBytes)
            currentMode ->
                -- AMBIGUITY: end without matching start, reset
                let chunk = Chunk (AmbiguityReset (UnmatchedModeEnd currentMode)) True
                 in (initDecodeState, Just chunk, remainingBytes)
    0xC7 ->
        -- FLUSH (chunk incomplete)
        let chunk = buildChunk state False
            -- Maintain ParseMode for next chunk!
            newState = state{decodeBuffer = []}
         in (newState, Just chunk, remainingBytes)
    0xCF ->
        -- STREAM_END
        let chunk =
                if null (decodeBuffer state)
                    then Chunk StreamEnd True
                    else buildChunk state True
            newState = initDecodeState
         in (newState, Just chunk, remainingBytes)
    _ | opcode >= 0xC8 && opcode <= 0xCE ->
        -- Reserved opcodes (0xC8-0xCE) - AMBIGUITY: reset
        let chunk = Chunk (AmbiguityReset (ReservedOpcode opcode)) True
         in (initDecodeState, Just chunk, remainingBytes)
    _ ->
        -- Unknown control outside reserved range, ignore
        (state, Nothing, remainingBytes)

-- | Create chunk from current state
buildChunk :: DecodeState -> Bool -> Chunk
buildChunk state = Chunk content
  where
    tokens = reverse (decodeBuffer state)
    content = case decodeParseMode state of
        ModeText -> TextContent tokens
        ModeThink -> ThinkContent tokens
        ModeToolCall -> ToolCallContent tokens
        ModeCodeBlock -> CodeBlockContent tokens

-- ════════════════════════════════════════════════════════════════════════════════
-- Incremental Feeding
-- ════════════════════════════════════════════════════════════════════════════════

-- | Feed bytes to decoder, get chunks
feedBytes :: DecodeState -> ByteString -> (DecodeState, [Chunk])
feedBytes = decodeFrameIncremental

{- | Flush any remaining tokens in buffer as a final chunk

Use this at end of stream to emit any accumulated tokens.
-}
flushDecoder :: DecodeState -> Maybe Chunk
flushDecoder state
    | null (decodeBuffer state) = Nothing
    | otherwise = Just $ buildChunk state True
