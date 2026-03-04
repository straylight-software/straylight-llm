{-# LANGUAGE OverloadedStrings #-}

{- | Model abstraction for SIGIL streaming

A Model captures the tokenizer-dependent facts needed to parse and emit
SIGIL frames correctly. This includes:
  - Vocabulary size and special token IDs
  - Semantic block delimiters (thinking, tool calls, code blocks)
  - Hot token table (model-specific frequency distribution)
  - Boundary tokens for semantic chunking

== Ingress Modes

SIGIL supports two fundamentally different ingress paths:

=== Passthrough Mode (jaylene-slide)

For OpenAI-compatible APIs (Baseten, Together, Fireworks, vLLM HTTP):

  * Provider sends SSE with JSON payloads containing text deltas
  * ~650 bytes per token of wire overhead
  * Must RE-TOKENIZE text back to token IDs for SIGIL encoding
  * Tokenizer is REQUIRED at ingress
  * Higher latency, but works with any compatible provider

=== Direct Mode (sigil-trtllm)

For custom TensorRT-LLM deployments with GPUDirect RDMA:

  * Token IDs come directly from inference engine via RDMA
  * Zero-copy from GPU memory
  * NO tokenization needed at ingress (already have token IDs)
  * Tokenizer only needed on consumer side for decode
  * Lowest possible latency

The Model abstraction serves both modes, but:
  - Passthrough mode uses 'modelTokenizer' to re-tokenize text deltas
  - Direct mode ignores 'modelTokenizer' at ingress

== Separation of Concerns

The model abstraction is separate from:
  - Provider: How to reach the inference endpoint (auth, transport)
  - StreamConfig: Per-request parameters (temperature, max_tokens)
  - StreamState: Per-stream mutable state (accumulated tokens, parse state)
-}
module Slide.Model (
    -- * Model specification
    Model (..),
    ModelCapabilities (..),
    SemanticDelimiters (..),

    -- * Ingress modes
    IngressMode (..),

    -- * Known models
    ModelFamily (..),
    modelFamilyFromName,

    -- * Model loading
    loadModel,
    modelFromFamily,

    -- * Tokenizer interface (abstract)
    Tokenizer (..),
    TokenizerConfig (..),

    -- * Identity tokenizer
    identityTokenizer,
) where

import Data.Bits ((.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Encoding.Error (OnDecodeError)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word32, Word8)

import Slide.HotTable (HotTable, defaultHotTable)

-- ════════════════════════════════════════════════════════════════════════════════
-- Ingress Modes
-- ════════════════════════════════════════════════════════════════════════════════

{- | How tokens arrive at the SIGIL encoder

This fundamentally affects what processing is needed at ingress.
-}
data IngressMode
    = {- | Text deltas via OpenAI-compatible API (SSE/JSON)

      Provider sends: @{"delta":{"content":"Hello"}}@
      We must: parse JSON, extract text, RE-TOKENIZE to get token IDs
      Tokenizer: REQUIRED at ingress
      Latency: ~1-5ms per chunk (HTTP + JSON parsing + tokenization)
      Use case: Baseten, Together, Fireworks, hosted vLLM
      -}
      IngressPassthrough
    | {- | Raw token IDs via direct protocol (RDMA, shared memory, etc.)

      Provider sends: token ID as Word32
      We must: just encode to SIGIL wire format
      Tokenizer: NOT needed at ingress (maybe needed at consumer for decode)
      Latency: ~1-10μs per token (zero-copy RDMA)
      Use case: Custom TensorRT-LLM with GPUDirect, local inference
      -}
      IngressDirect
    | {- | Provider gives token IDs AND text (some custom deployments)

      Useful when you control the inference server and can emit both.
      Allows SIGIL encoding without re-tokenization while still
      providing text for consumers that want it.
      -}
      IngressHybrid
    deriving stock (Show, Eq, Ord)

-- ════════════════════════════════════════════════════════════════════════════════
-- Model Specification
-- ════════════════════════════════════════════════════════════════════════════════

{- | Complete model specification for SIGIL streaming

This is the unit of configuration that determines how tokens are parsed
and emitted. Multiple concurrent streams can share a Model (it's immutable),
but each stream has its own StreamState.
-}
data Model = Model
    { modelName :: !Text
    -- ^ Human-readable name (e.g., "Qwen3-235B-A22B")
    , modelFamily :: !ModelFamily
    -- ^ Model family for family-specific parsing rules
    , modelVocabSize :: !Int
    -- ^ Vocabulary size (e.g., 151936 for Qwen, 128256 for Llama3)
    , modelCapabilities :: !ModelCapabilities
    -- ^ What features this model supports
    , modelDelimiters :: !SemanticDelimiters
    -- ^ Token IDs for semantic block delimiters
    , modelHotTable :: !HotTable
    -- ^ Frequency-optimized hot token encoding
    , modelBoundaries :: !(VU.Vector Bool)
    -- ^ Token IDs that are natural chunk boundaries
    , modelTokenizer :: !Tokenizer
    -- ^ Tokenizer for this model (encode/decode)
    }

{- | Model capabilities (what features are available)

These are model-level capabilities, not per-request toggles.
A model either has thinking support in its training or it doesn't.
-}
data ModelCapabilities = ModelCapabilities
    { capabilityThinking :: !Bool
    -- ^ Model was trained with thinking/reasoning traces
    , capabilityToolCalling :: !Bool
    -- ^ Model supports structured tool/function calling
    , capabilityCodeBlocks :: !Bool
    -- ^ Model reliably emits fenced code blocks (most do)
    , capabilityStreaming :: !Bool
    -- ^ Model/provider supports token-level streaming
    }
    deriving stock (Show, Eq)

{- | Semantic block delimiters

Supports both token ID matching (for direct ingress) and text pattern
matching (for passthrough ingress). Token IDs are model-specific because
different tokenizers assign different IDs to the same strings.
-}
data SemanticDelimiters = SemanticDelimiters
    { -- Token-based delimiters (for direct ingress with token IDs)
      delimThinkStartToken :: !(Maybe Word32)
    -- ^ Token ID for <think> or equivalent (Nothing if unsupported)
    , delimThinkEndToken :: !(Maybe Word32)
    -- ^ Token ID for </think> or equivalent
    , delimToolCallStartToken :: !(Maybe Word32)
    -- ^ Token ID for tool call block start
    , delimToolCallEndToken :: !(Maybe Word32)
    -- ^ Token ID for tool call block end
    , delimCodeFenceToken :: !(Maybe Word32)
    -- ^ Token ID for ``` (toggles code block state)
    , delimEosToken :: !Word32
    -- ^ End-of-sequence token ID
    , delimBosToken :: !(Maybe Word32)
    -- ^ Beginning-of-sequence token ID (if used)
    , -- Text-based delimiters (for passthrough ingress with text deltas)
      delimThinkStartText :: !(Maybe Text)
    -- ^ Text pattern for thinking start (e.g., "<think>", "<reasoning>")
    , delimThinkEndText :: !(Maybe Text)
    -- ^ Text pattern for thinking end
    , delimToolCallStartText :: !(Maybe Text)
    -- ^ Text pattern for tool call start
    , delimToolCallEndText :: !(Maybe Text)
    -- ^ Text pattern for tool call end
    , delimCodeFenceText :: !Text
    -- ^ Text pattern for code fence (typically "```")
    }
    deriving stock (Show, Eq)

-- ════════════════════════════════════════════════════════════════════════════════
-- Model Families
-- ════════════════════════════════════════════════════════════════════════════════

{- | Known model families

Model families share tokenizers and special token conventions.
This is the coarsest level of model identification.
-}
data ModelFamily
    = -- | Qwen 2.5/3 series (151936 vocab)
      FamilyQwen3
    | -- | Llama 3.x series (128256 vocab)
      FamilyLlama3
    | -- | DeepSeek V3 series
      FamilyDeepSeekV3
    | -- | Moonshot Kimi K2 series
      FamilyKimi
    | -- | Mistral/Mixtral series
      FamilyMistral
    | -- | Anthropic Claude (via API, no tokenizer access)
      FamilyClaude
    | -- | OpenAI GPT-4 (via API, no tokenizer access)
      FamilyGPT4
    | -- | Unknown model, use conservative defaults
      FamilyUnknown
    deriving stock (Show, Eq, Ord)

{- | Attempt to identify model family from model name

This is heuristic-based and may fail for unusual naming conventions.
Falls back to FamilyUnknown which uses conservative chunking.
-}
modelFamilyFromName :: Text -> ModelFamily
modelFamilyFromName name
    | matchesAny ["qwen", "qwen2", "qwen3"] = FamilyQwen3
    | matchesAny ["llama-3", "llama3", "meta-llama"] = FamilyLlama3
    | matchesAny ["deepseek", "deepseek-v3"] = FamilyDeepSeekV3
    | matchesAny ["kimi", "moonshot"] = FamilyKimi
    | matchesAny ["mistral", "mixtral"] = FamilyMistral
    | matchesAny ["claude"] = FamilyClaude
    | matchesAny ["gpt-4", "gpt4"] = FamilyGPT4
    | otherwise = FamilyUnknown
  where
    lowerName = T.toLower name
    matchesAny = any (`T.isInfixOf` lowerName)

-- ════════════════════════════════════════════════════════════════════════════════
-- Tokenizer Interface
-- ════════════════════════════════════════════════════════════════════════════════

{- | Abstract tokenizer interface

All operations are in IO because real tokenizers (via FFI to tokenizers-cpp)
involve foreign memory and potential exceptions. Even "pure" tokenizers like
the identity tokenizer use IO for consistency - the cost is negligible and
it avoids a minefield of unsafePerformIO + FFI + GC interactions.
-}
data Tokenizer = Tokenizer
    { tokenizerEncode :: !(Text -> IO [Word32])
    -- ^ Encode text to token IDs
    , tokenizerDecode :: !([Word32] -> IO Text)
    -- ^ Decode token IDs to text
    , tokenizerDecodeOne :: !(Word32 -> IO (Maybe ByteString))
    -- ^ Decode single token to bytes (for incremental output)
    , tokenizerVocabSize :: !Int
    -- ^ Total vocabulary size
    , tokenizerConfig :: !TokenizerConfig
    -- ^ Configuration/metadata
    }

-- | Tokenizer configuration and metadata
data TokenizerConfig = TokenizerConfig
    { tokenizerModelId :: !Text
    -- ^ HuggingFace model ID or local path
    , tokenizerHash :: !ByteString
    -- ^ Content-addressed hash of tokenizer config
    }
    deriving stock (Show, Eq)

-- ════════════════════════════════════════════════════════════════════════════════
-- Model Loading
-- ════════════════════════════════════════════════════════════════════════════════

{- | Load model configuration from model name

This will eventually:
  1. Identify model family from name
  2. Load tokenizer (from cache or download)
  3. Look up special token IDs
  4. Load or generate hot table

For now, returns a stub model with defaults.
-}
loadModel :: Text -> IO Model
loadModel name = do
    let family = modelFamilyFromName name
    modelFromFamily name family

{- | Create model from family with defaults

This uses hardcoded knowledge about model families to set up
reasonable defaults. Real usage should load from config files.
-}
modelFromFamily :: Text -> ModelFamily -> IO Model
modelFromFamily name family = do
    let (vocabSize, capabilities, delimiters) = familyDefaults family

    pure
        Model
            { modelName = name
            , modelFamily = family
            , modelVocabSize = vocabSize
            , modelCapabilities = capabilities
            , modelDelimiters = delimiters
            , modelHotTable = defaultHotTable
            , modelBoundaries = defaultBoundaries vocabSize
            , modelTokenizer = stubTokenizer vocabSize
            }

-- | Get default configuration for a model family
familyDefaults :: ModelFamily -> (Int, ModelCapabilities, SemanticDelimiters)
familyDefaults family = case family of
    FamilyQwen3 ->
        ( 151936
        , ModelCapabilities
            { capabilityThinking = True
            , capabilityToolCalling = True
            , capabilityCodeBlocks = True
            , capabilityStreaming = True
            }
        , SemanticDelimiters
            { delimThinkStartToken = Just 151646 -- <think> (estimated)
            , delimThinkEndToken = Just 151647 -- </think>
            , delimToolCallStartToken = Just 151648 -- <tool_call>
            , delimToolCallEndToken = Just 151649 -- </tool_call>
            , delimCodeFenceToken = Just 74 -- ``` (common)
            , delimEosToken = 151645 -- <|endoftext|>
            , delimBosToken = Just 151643 -- <|im_start|>
            , delimThinkStartText = Just "<think>"
            , delimThinkEndText = Just "</think>"
            , delimToolCallStartText = Just "<tool_call>"
            , delimToolCallEndText = Just "</tool_call>"
            , delimCodeFenceText = "```"
            }
        )
    FamilyLlama3 ->
        ( 128256
        , ModelCapabilities
            { capabilityThinking = False -- Base Llama3 doesn't have thinking
            , capabilityToolCalling = True
            , capabilityCodeBlocks = True
            , capabilityStreaming = True
            }
        , SemanticDelimiters
            { delimThinkStartToken = Nothing
            , delimThinkEndToken = Nothing
            , delimToolCallStartToken = Nothing -- Llama uses different format
            , delimToolCallEndToken = Nothing
            , delimCodeFenceToken = Just 74
            , delimEosToken = 128009 -- <|eot_id|>
            , delimBosToken = Just 128000 -- <|begin_of_text|>
            , delimThinkStartText = Nothing
            , delimThinkEndText = Nothing
            , delimToolCallStartText = Nothing
            , delimToolCallEndText = Nothing
            , delimCodeFenceText = "```"
            }
        )
    FamilyDeepSeekV3 ->
        ( 129280
        , ModelCapabilities
            { capabilityThinking = True -- DeepSeek R1 has thinking
            , capabilityToolCalling = True
            , capabilityCodeBlocks = True
            , capabilityStreaming = True
            }
        , SemanticDelimiters
            { delimThinkStartToken = Just 129025 -- <think> (estimated)
            , delimThinkEndToken = Just 129026
            , delimToolCallStartToken = Nothing
            , delimToolCallEndToken = Nothing
            , delimCodeFenceToken = Just 74
            , delimEosToken = 129024
            , delimBosToken = Nothing
            , delimThinkStartText = Just "<think>"
            , delimThinkEndText = Just "</think>"
            , delimToolCallStartText = Nothing
            , delimToolCallEndText = Nothing
            , delimCodeFenceText = "```"
            }
        )
    FamilyKimi ->
        ( 163840
        , ModelCapabilities
            { capabilityThinking = True
            , capabilityToolCalling = True
            , capabilityCodeBlocks = True
            , capabilityStreaming = True
            }
        , SemanticDelimiters
            { delimThinkStartToken = Just 163800 -- Placeholder
            , delimThinkEndToken = Just 163801
            , delimToolCallStartToken = Just 163802
            , delimToolCallEndToken = Just 163803
            , delimCodeFenceToken = Just 74
            , delimEosToken = 163839
            , delimBosToken = Just 163838
            , delimThinkStartText = Just "<think>"
            , delimThinkEndText = Just "</think>"
            , delimToolCallStartText = Just "<tool_call>"
            , delimToolCallEndText = Just "</tool_call>"
            , delimCodeFenceText = "```"
            }
        )
    -- Unknown or API-only models: conservative defaults
    _ ->
        ( 150000
        , ModelCapabilities
            { capabilityThinking = False
            , capabilityToolCalling = False
            , capabilityCodeBlocks = True
            , capabilityStreaming = True
            }
        , SemanticDelimiters
            { delimThinkStartToken = Nothing
            , delimThinkEndToken = Nothing
            , delimToolCallStartToken = Nothing
            , delimToolCallEndToken = Nothing
            , delimCodeFenceToken = Nothing -- Don't assume code fence token
            , delimEosToken = 0 -- Will need to detect differently
            , delimBosToken = Nothing
            , delimThinkStartText = Nothing
            , delimThinkEndText = Nothing
            , delimToolCallStartText = Nothing
            , delimToolCallEndText = Nothing
            , delimCodeFenceText = "```" -- Safe default
            }
        )

-- ════════════════════════════════════════════════════════════════════════════════
-- Identity Tokenizer
-- ════════════════════════════════════════════════════════════════════════════════

{- | Identity tokenizer: UTF-8 bytes are token IDs

This is the simplest possible tokenizer:
  - encode: Text -> UTF-8 bytes -> each byte is a token ID (0-255)
  - decode: token IDs (0-255) -> bytes -> UTF-8 text

Use cases:
  1. Passthrough baseline - works without loading real tokenizers
  2. Bug basher - run same stream through identity + real tokenizer, diff output
  3. Testing - deterministic, no external dependencies
  4. Fallback - when real tokenizer unavailable

The SIGIL wire format doesn't care what token IDs mean. A consumer can:
  - Use real tokenizer to decode (if available)
  - Interpret identity-tokenized IDs as raw UTF-8 bytes

Hot table effectiveness: ~50% of English text is in ASCII 32-126 range,
so even with identity tokenizer, hot encoding provides reasonable compression.
-}
identityTokenizer :: Tokenizer
identityTokenizer =
    Tokenizer
        { tokenizerEncode = pure . encodeUtf8AsTokens
        , tokenizerDecode = pure . decodeTokensAsUtf8
        , tokenizerDecodeOne = pure . decodeSingleToken
        , tokenizerVocabSize = 256 -- One token per byte value
        , tokenizerConfig =
            TokenizerConfig
                { tokenizerModelId = "identity"
                , tokenizerHash = identityTokenizerHash
                }
        }
  where
    -- Encode text as UTF-8 bytes, each byte becomes a token ID
    encodeUtf8AsTokens :: Text -> [Word32]
    encodeUtf8AsTokens text =
        map fromIntegral (BS.unpack (TE.encodeUtf8 text))

    -- Decode token IDs as UTF-8 bytes back to text
    decodeTokensAsUtf8 :: [Word32] -> Text
    decodeTokensAsUtf8 tokens =
        TE.decodeUtf8With lenientDecode (BS.pack (map truncateToWord8 tokens))

    -- Decode single token to its byte representation
    decodeSingleToken :: Word32 -> Maybe ByteString
    decodeSingleToken tokenId
        | tokenId < 256 = Just (BS.singleton (fromIntegral tokenId))
        | otherwise = Nothing -- Invalid for identity tokenizer
    truncateToWord8 :: Word32 -> Word8
    truncateToWord8 = fromIntegral . (.&. 0xFF)

    lenientDecode :: OnDecodeError
    lenientDecode _ _ = Just '\xFFFD' -- Replacement character

    -- Fixed hash for identity tokenizer (it never changes)
    identityTokenizerHash :: ByteString
    identityTokenizerHash =
        BS.pack
            [ 0x69
            , 0x64
            , 0x65
            , 0x6e
            , 0x74
            , 0x69
            , 0x74
            , 0x79 -- "identity"
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x00
            , 0x01 -- version 1
            ]

-- ════════════════════════════════════════════════════════════════════════════════
-- Default Configurations
-- ════════════════════════════════════════════════════════════════════════════════

{- | Default boundary tokens for identity tokenizer

For UTF-8 byte tokenization, boundaries are ASCII control/punctuation:
  - 0x0A (10): newline
  - 0x0D (13): carriage return
  - 0x3B (59): semicolon
  - 0x7D (125): close brace
  - 0x29 (41): close paren
  - 0x5D (93): close bracket
-}
defaultBoundaries :: Int -> VU.Vector Bool
defaultBoundaries vocabSize = VU.generate vocabSize $ \tokenId ->
    tokenId == 10 -- newline
        || tokenId == 13 -- carriage return
        || tokenId == 59 -- semicolon
        || tokenId == 125 -- }
        || tokenId == 41 -- )
        || tokenId == 93 -- ]

{- | Stub tokenizer (deprecated, use identityTokenizer)

This exists for backwards compatibility but delegates to identityTokenizer.
-}
stubTokenizer :: Int -> Tokenizer
stubTokenizer _vocabSize = identityTokenizer
