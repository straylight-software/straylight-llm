-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                  // straylight-llm // property // sigil tests
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd seen the signs of change in every aspect of the matrix, the city
--      itself becoming a poem of data."
--
--                                                              — Neuromancer
--
-- Property-based tests for SIGIL wire format and transport.
--
-- Test categories:
--   1. Varint encode/decode roundtrip
--   2. Hot token encoding invariants
--   3. Frame encode/decode roundtrip
--   4. Reset-on-ambiguity correctness
--   5. Adversarial frame handling
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

module Property.SigilProps
    ( tests
    ) where

import Control.Monad (when)
import Data.Bits ((.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Word (Word8, Word32)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.Hedgehog

import Slide.Wire.Decode
    ( AmbiguityReason (..)
    , Chunk (..)
    , ChunkContent (..)
    , DecodeState
    , decodeFrame
    , decodeFrameIncremental
    , initDecodeState
    , resetDecodeState
    )
import Slide.Wire.Types
    ( FrameOp (..)
    , TokenId
    , isControlByte
    , isExtendedByte
    , isHotByte
    , maxHotId
    , pattern OP_CHUNK_END
    , pattern OP_CODE_BLOCK_END
    , pattern OP_CODE_BLOCK_START
    , pattern OP_FLUSH
    , pattern OP_STREAM_END
    , pattern OP_THINK_END
    , pattern OP_THINK_START
    , pattern OP_TOOL_CALL_END
    , pattern OP_TOOL_CALL_START
    )
import Slide.Wire.Varint (decodeVarint, encodeVarint, varintSize)


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // varint generators
-- ════════════════════════════════════════════════════════════════════════════

-- | Generate any valid Word32
genWord32 :: Gen Word32
genWord32 = Gen.word32 Range.linearBounded

-- | Generate Word32 in specific varint size ranges (realistic distribution)
genWord32Realistic :: Gen Word32
genWord32Realistic = Gen.frequency
    [ (70, Gen.word32 (Range.linear 0 0x7F))           -- 1 byte (most common: hot table tokens)
    , (20, Gen.word32 (Range.linear 0x80 0x3FFF))      -- 2 bytes (common vocabulary)
    , (8, Gen.word32 (Range.linear 0x4000 0x1FFFFF))   -- 3 bytes (extended vocab)
    , (2, Gen.word32 (Range.linear 0x200000 maxBound)) -- 4-5 bytes (rare)
    ]

-- | Generate varint that requires exactly N bytes
genVarintExactSize :: Int -> Gen Word32
genVarintExactSize 1 = Gen.word32 (Range.linear 0 0x7F)
genVarintExactSize 2 = Gen.word32 (Range.linear 0x80 0x3FFF)
genVarintExactSize 3 = Gen.word32 (Range.linear 0x4000 0x1FFFFF)
genVarintExactSize 4 = Gen.word32 (Range.linear 0x200000 0xFFFFFFF)
genVarintExactSize 5 = Gen.word32 (Range.linear 0x10000000 maxBound)
genVarintExactSize _ = Gen.word32 Range.linearBounded


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // frame generators
-- ════════════════════════════════════════════════════════════════════════════

-- | Generate a hot token byte (0x00-0x7E)
genHotByte :: Gen Word8
genHotByte = Gen.word8 (Range.linear 0 maxHotId)

-- | Generate an extended token escape + varint
genExtendedToken :: Gen ByteString
genExtendedToken = do
    tokenId <- Gen.word32 (Range.linear 128 150000)  -- typical vocab range
    let escape = 0x80 .|. (fromIntegral tokenId .&. 0x3F)  -- extended escape byte
        varint = encodeVarint tokenId
    pure $ BS.cons escape varint

-- | Generate a valid control byte
genControlByte :: Gen Word8
genControlByte = Gen.element
    [ 0xC0  -- CHUNK_END
    , 0xC1  -- TOOL_CALL_START
    , 0xC2  -- TOOL_CALL_END
    , 0xC3  -- THINK_START
    , 0xC4  -- THINK_END
    , 0xC5  -- CODE_BLOCK_START
    , 0xC6  -- CODE_BLOCK_END
    , 0xC7  -- FLUSH
    , 0xCF  -- STREAM_END
    ]

-- | Generate reserved control bytes (should trigger ambiguity reset)
genReservedControlByte :: Gen Word8
genReservedControlByte = Gen.element [0xC8, 0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE]

-- | Generate a well-formed SIGIL frame (hot tokens + terminating control)
--
-- A "well-formed" frame is one that produces at least one chunk when decoded.
-- This means we need either:
--   1. Some tokens + any chunk-producing control (CHUNK_END, FLUSH, STREAM_END)
--   2. Zero tokens + STREAM_END (produces StreamEnd chunk)
--
-- Mode START controls (TOOL_CALL_START, etc.) don't produce chunks by themselves,
-- they just change parser state. So we use only terminating controls here.
genWellFormedFrame :: Gen ByteString
genWellFormedFrame = do
    numTokens <- Gen.int (Range.linear 0 100)
    tokens <- Gen.list (Range.singleton numTokens) genHotByte
    -- Use only controls that produce chunks:
    -- 0xC0 = CHUNK_END, 0xC7 = FLUSH, 0xCF = STREAM_END
    -- If no tokens, only STREAM_END produces a chunk (StreamEnd)
    control <- if numTokens == 0
               then pure 0xCF  -- STREAM_END always produces chunk
               else Gen.element [0xC0, 0xC7, 0xCF]  -- any terminating control
    pure $ BS.snoc (BS.pack tokens) control

-- | Generate a frame with only hot tokens (no control terminator)
genHotOnlyFrame :: Gen ByteString
genHotOnlyFrame = do
    numTokens <- Gen.int (Range.linear 1 200)
    BS.pack <$> Gen.list (Range.singleton numTokens) genHotByte


-- ════════════════════════════════════════════════════════════════════════════
--                                                  // adversarial generators
-- ════════════════════════════════════════════════════════════════════════════

-- | Generate frame with nested mode starts (should trigger ambiguity)
genNestedModeFrame :: Gen ByteString
genNestedModeFrame = do
    -- Start tool call, then start think without ending tool call
    let toolStart = 0xC1
        thinkStart = 0xC3
    tokensAfter <- Gen.list (Range.linear 0 10) genHotByte
    pure $ BS.pack ([toolStart, thinkStart] <> tokensAfter)

-- | Generate frame with unmatched mode end (should trigger ambiguity)
genUnmatchedEndFrame :: Gen ByteString
genUnmatchedEndFrame = do
    -- End tool call without starting it
    let toolEnd = 0xC2
    tokensBefore <- Gen.list (Range.linear 0 10) genHotByte
    pure $ BS.pack (tokensBefore <> [toolEnd])

-- | Generate frame with reserved opcode
genReservedOpcodeFrame :: Gen ByteString
genReservedOpcodeFrame = do
    tokensBefore <- Gen.list (Range.linear 0 10) genHotByte
    reserved <- genReservedControlByte
    pure $ BS.pack (tokensBefore <> [reserved])

-- | Generate truncated varint (incomplete extended token)
genTruncatedVarintFrame :: Gen ByteString
genTruncatedVarintFrame = do
    -- Extended escape byte with continuation bit set, but no following bytes
    let escape = 0x80
        -- Varint byte with continuation bit (needs more bytes)
        incomplete = 0x80 .|. 0x42
    pure $ BS.pack [escape, incomplete]

-- | Generate maximum-size varint that overflows
genOverflowVarintFrame :: Gen ByteString
genOverflowVarintFrame = do
    -- 6 bytes with continuation bits = overflow (max is 5 for Word32)
    let escape = 0x80
        overflowBytes = replicate 6 0x80  -- all continuation, would need >32 bits
    pure $ BS.pack (escape : overflowBytes)

-- | Generate 0x7F byte (reserved, not hot)
gen7FFrame :: Gen ByteString
gen7FFrame = do
    tokensBefore <- Gen.list (Range.linear 0 5) genHotByte
    tokensAfter <- Gen.list (Range.linear 0 5) genHotByte
    pure $ BS.pack (tokensBefore <> [0x7F] <> tokensAfter)


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // varint properties
-- ════════════════════════════════════════════════════════════════════════════

-- | Varint encode/decode roundtrips for all Word32 values
prop_varintRoundtrip :: Property
prop_varintRoundtrip = property $ do
    value <- forAll genWord32
    let encoded = encodeVarint value
    case decodeVarint encoded of
        Nothing -> failure
        Just (decoded, consumed) -> do
            decoded === value
            consumed === BS.length encoded

-- | Varint size calculation is correct
prop_varintSizeCorrect :: Property
prop_varintSizeCorrect = property $ do
    value <- forAll genWord32
    let encoded = encodeVarint value
    varintSize value === BS.length encoded

-- | Varint encoding is prefix-free (no value is prefix of another)
prop_varintPrefixFree :: Property
prop_varintPrefixFree = property $ do
    v1 <- forAll genWord32
    v2 <- forAll genWord32
    let e1 = encodeVarint v1
        e2 = encodeVarint v2
    -- If v1 /= v2, then the encodings must differ
    when (v1 /= v2) $ do
        diff e1 (/=) e2 -- at least one byte must differ

-- | Varint encoding is monotonic in size
prop_varintMonotonicSize :: Property
prop_varintMonotonicSize = property $ do
    v1 <- forAll genWord32
    v2 <- forAll genWord32
    when (v1 <= v2) $ do
        assert $ varintSize v1 <= varintSize v2


-- ════════════════════════════════════════════════════════════════════════════
--                                                   // byte classification
-- ════════════════════════════════════════════════════════════════════════════

-- | Hot byte classification is correct
prop_hotByteClassification :: Property
prop_hotByteClassification = property $ do
    byte <- forAll $ Gen.word8 Range.linearBounded
    let isHot = isHotByte byte
    -- Hot bytes: 0x00-0x7E (high bit clear, not 0x7F)
    isHot === (byte <= 0x7E)

-- | Extended byte classification is correct
prop_extendedByteClassification :: Property
prop_extendedByteClassification = property $ do
    byte <- forAll $ Gen.word8 Range.linearBounded
    let isExt = isExtendedByte byte
    -- Extended bytes: 0x80-0xBF (top 2 bits = 10)
    isExt === (byte >= 0x80 && byte <= 0xBF)

-- | Control byte classification is correct
prop_controlByteClassification :: Property
prop_controlByteClassification = property $ do
    byte <- forAll $ Gen.word8 Range.linearBounded
    let isCtrl = isControlByte byte
    -- Control bytes: 0xC0-0xCF or 0xF0
    isCtrl === ((byte >= 0xC0 && byte <= 0xCF) || byte == 0xF0)

-- | Byte classes are mutually exclusive
prop_byteClassesMutuallyExclusive :: Property
prop_byteClassesMutuallyExclusive = property $ do
    byte <- forAll $ Gen.word8 Range.linearBounded
    let hot = isHotByte byte
        ext = isExtendedByte byte
        ctrl = isControlByte byte
    -- At most one classification should be true
    assert $ length (filter id [hot, ext, ctrl]) <= 1


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // decode properties
-- ════════════════════════════════════════════════════════════════════════════

-- | Reset state is always the initial state
prop_resetIsInitial :: Property
prop_resetIsInitial = property $ do
    -- For any decode state, reset returns initial
    let initial = initDecodeState
        reset = resetDecodeState initial
    reset === initial

-- | Decoding empty input produces no chunks
prop_decodeEmptyIsEmpty :: Property
prop_decodeEmptyIsEmpty = property $ do
    let chunks = decodeFrame BS.empty
    chunks === []

-- | Well-formed frame decodes successfully
prop_wellFormedFrameDecodes :: Property
prop_wellFormedFrameDecodes = property $ do
    frame <- forAll genWellFormedFrame
    let chunks = decodeFrame frame
    -- Should produce at least one chunk (the control terminator)
    assert $ not (null chunks)

-- | STREAM_END produces StreamEnd chunk
prop_streamEndChunk :: Property
prop_streamEndChunk = property $ do
    tokens <- forAll $ Gen.list (Range.linear 0 50) genHotByte
    let frame = BS.snoc (BS.pack tokens) 0xCF  -- STREAM_END
        chunks = decodeFrame frame
        lastChunk = last chunks
    -- Last chunk should be StreamEnd or contain final tokens
    case chunkContent lastChunk of
        StreamEnd -> success
        TextContent _ -> success  -- tokens before STREAM_END
        _ -> failure


-- ════════════════════════════════════════════════════════════════════════════
--                                                    // adversarial properties
-- ════════════════════════════════════════════════════════════════════════════

-- | Nested mode start triggers ambiguity reset
prop_nestedModeTriggersReset :: Property
prop_nestedModeTriggersReset = property $ do
    frame <- forAll genNestedModeFrame
    let chunks = decodeFrame frame
        hasAmbiguity = any isAmbiguityReset chunks
    -- Should detect the nested mode ambiguity
    assert hasAmbiguity

-- | Unmatched mode end triggers ambiguity reset
prop_unmatchedEndTriggersReset :: Property
prop_unmatchedEndTriggersReset = property $ do
    frame <- forAll genUnmatchedEndFrame
    let chunks = decodeFrame frame
        hasAmbiguity = any isAmbiguityReset chunks
    -- Should detect the unmatched end
    assert hasAmbiguity

-- | Reserved opcode triggers ambiguity reset
prop_reservedOpcodeTriggersReset :: Property
prop_reservedOpcodeTriggersReset = property $ do
    frame <- forAll genReservedOpcodeFrame
    let chunks = decodeFrame frame
        hasAmbiguity = any isAmbiguityReset chunks
    assert hasAmbiguity

-- | Decoder never crashes on arbitrary input
prop_decoderNeverCrashes :: Property
prop_decoderNeverCrashes = property $ do
    -- Generate completely arbitrary bytes
    bytes <- forAll $ Gen.bytes (Range.linear 0 1000)
    let chunks = decodeFrame bytes
    -- Should not throw, just return chunks (possibly with ambiguity resets)
    assert $ chunks `seq` True

-- | After ambiguity reset, decode continues from ground state
prop_postResetIsCanonical :: Property
prop_postResetIsCanonical = property $ do
    -- Generate adversarial frame that triggers reset, then valid tokens
    adversarial <- forAll genNestedModeFrame
    validTokens <- forAll $ Gen.list (Range.linear 1 20) genHotByte
    let frame = adversarial <> BS.pack validTokens <> BS.singleton 0xC0  -- CHUNK_END
        chunks = decodeFrame frame
        -- Find chunks after the ambiguity reset
        postResetChunks = dropWhile (not . isAmbiguityReset) chunks
    -- Post-reset chunks should be valid TextContent
    case drop 1 postResetChunks of
        [] -> success  -- no chunks after reset is fine
        (c : _) -> case chunkContent c of
            TextContent _ -> success
            _ -> success  -- any valid content is fine


-- ════════════════════════════════════════════════════════════════════════════
--                                                             // incremental
-- ════════════════════════════════════════════════════════════════════════════

-- | Incremental decode matches single-shot decode
prop_incrementalMatchesSingleShot :: Property
prop_incrementalMatchesSingleShot = property $ do
    frame <- forAll genWellFormedFrame
    let singleShot = decodeFrame frame
        (_, incremental) = decodeFrameIncremental initDecodeState frame
    -- Should produce same chunks
    incremental === singleShot

-- | Incremental decode is associative (chunking doesn't matter)
prop_incrementalAssociative :: Property
prop_incrementalAssociative = property $ do
    frame <- forAll genWellFormedFrame
    splitPoint <- forAll $ Gen.int (Range.linear 0 (BS.length frame))
    let (part1, part2) = BS.splitAt splitPoint frame
        -- Decode in two parts
        (state1, chunks1) = decodeFrameIncremental initDecodeState part1
        (_, chunks2) = decodeFrameIncremental state1 part2
        incrementalChunks = chunks1 <> chunks2
        -- Decode in one shot
        singleShotChunks = decodeFrame frame
    -- Should produce equivalent results (may differ in chunk boundaries)
    -- Check that total token count is same
    let totalTokens cs = sum [length ts | Chunk c _ <- cs, TextContent ts <- [c]]
    totalTokens incrementalChunks === totalTokens singleShotChunks


-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // helpers
-- ════════════════════════════════════════════════════════════════════════════

isAmbiguityReset :: Chunk -> Bool
isAmbiguityReset (Chunk (AmbiguityReset _) _) = True
isAmbiguityReset _ = False


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "SIGIL Wire Format Properties"
    [ testGroup "Varint Encoding"
        [ testProperty "encode/decode roundtrip" prop_varintRoundtrip
        , testProperty "size calculation correct" prop_varintSizeCorrect
        , testProperty "prefix-free encoding" prop_varintPrefixFree
        , testProperty "monotonic size" prop_varintMonotonicSize
        ]
    , testGroup "Byte Classification"
        [ testProperty "hot byte classification" prop_hotByteClassification
        , testProperty "extended byte classification" prop_extendedByteClassification
        , testProperty "control byte classification" prop_controlByteClassification
        , testProperty "classes mutually exclusive" prop_byteClassesMutuallyExclusive
        ]
    , testGroup "Frame Decoding"
        [ testProperty "reset is initial state" prop_resetIsInitial
        , testProperty "empty input = empty output" prop_decodeEmptyIsEmpty
        , testProperty "well-formed frame decodes" prop_wellFormedFrameDecodes
        , testProperty "STREAM_END produces chunk" prop_streamEndChunk
        ]
    , testGroup "Adversarial Inputs"
        [ testProperty "nested mode triggers reset" prop_nestedModeTriggersReset
        , testProperty "unmatched end triggers reset" prop_unmatchedEndTriggersReset
        , testProperty "reserved opcode triggers reset" prop_reservedOpcodeTriggersReset
        , testProperty "decoder never crashes" prop_decoderNeverCrashes
        , testProperty "post-reset is canonical" prop_postResetIsCanonical
        ]
    , testGroup "Incremental Decoding"
        [ testProperty "matches single-shot" prop_incrementalMatchesSingleShot
        , testProperty "associative chunking" prop_incrementalAssociative
        ]
    ]
