-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                            // straylight-llm // generators
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd operated on an almost permanent adrenaline high."
--
--                                                              — Neuromancer
--
-- Hedgehog generators for property testing. Generates realistic test data
-- matching OpenAI API schemas.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Property.Generators
    ( -- * Semantic Types
      genModelId
    , genTemperature
    , genTopP
    , genMaxTokens
    , genUserId
    , genToolCallId
    , genResponseId
    , genTimestamp
    , genFinishReason

      -- * Messages
    , genRole
    , genMessage
    , genContentPart
    , genMessageContent

      -- * Tool Calls
    , genToolCall
    , genFunctionCall
    , genToolCallDelta
    , genFunctionCallDelta

      -- * Request Parameters
    , genStopSequence
    , genLogitBias
    , genToolDef
    , genToolFunction
    , genJsonSchema
    , genToolChoice
    , genToolChoiceFunction
    , genResponseFormat
    , genEmbeddingInput
    , genDeltaContent

      -- * Chat Completions
    , genChatRequest
    , genChatResponse
    , genChoice
    , genChoiceDelta
    , genUsage

      -- * Completions (legacy)
    , genCompletionRequest
    , genCompletionResponse
    , genCompletionChoice

      -- * Embeddings
    , genEmbeddingRequest
    , genEmbeddingResponse
    , genEmbeddingData

      -- * Models
    , genModel
    , genModelList

      -- * Streaming
    , genStreamChunk

      -- * Errors
    , genApiError
    , genErrorDetail

      -- * Helpers
    , genText
    , genNonEmptyText
    ) where

import Data.Aeson (Object, ToJSON (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.List qualified
import Data.Text (Text)
import Data.Vector qualified as V
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Types


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // helpers
-- ════════════════════════════════════════════════════════════════════════════

genText :: Gen Text
genText = Gen.text (Range.linear 0 100) Gen.alphaNum

genNonEmptyText :: Gen Text
genNonEmptyText = Gen.text (Range.linear 1 100) Gen.alphaNum

genDouble :: Gen Double
genDouble = Gen.double (Range.linearFrac 0.0 2.0)

genPositiveDouble :: Gen Double
genPositiveDouble = Gen.double (Range.linearFrac 0.0 100.0)

genInt :: Gen Int
genInt = Gen.int (Range.linear 0 10000)

genPositiveInt :: Gen Int
genPositiveInt = Gen.int (Range.linear 1 10000)


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // semantic types
-- ════════════════════════════════════════════════════════════════════════════

genModelId :: Gen ModelId
genModelId = ModelId <$> Gen.element
    [ "gpt-4"
    , "gpt-4-turbo"
    , "gpt-3.5-turbo"
    , "claude-3-opus"
    , "claude-3-sonnet"
    , "llama-3-70b"
    ]

genTemperature :: Gen Temperature
genTemperature = Temperature <$> Gen.double (Range.linearFrac 0.0 2.0)

genTopP :: Gen TopP
genTopP = TopP <$> Gen.double (Range.linearFrac 0.0 1.0)

genMaxTokens :: Gen MaxTokens
genMaxTokens = MaxTokens <$> Gen.int (Range.linear 1 4096)

genUserId :: Gen UserId
genUserId = UserId <$> genNonEmptyText

genToolCallId :: Gen ToolCallId
genToolCallId = ToolCallId <$> Gen.text (Range.singleton 24) Gen.alphaNum

genResponseId :: Gen ResponseId
genResponseId = ResponseId <$> Gen.text (Range.singleton 32) Gen.alphaNum

genTimestamp :: Gen Timestamp
genTimestamp = Timestamp <$> Gen.int (Range.linear 1700000000 1800000000)

genFinishReason :: Gen FinishReason
genFinishReason = FinishReason <$> Gen.element
    [ "stop"
    , "length"
    , "tool_calls"
    , "content_filter"
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // roles
-- ════════════════════════════════════════════════════════════════════════════

genRole :: Gen Role
genRole = Gen.element [System, User, Assistant, Tool]


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // tool calls
-- ════════════════════════════════════════════════════════════════════════════

genFunctionCall :: Gen FunctionCall
genFunctionCall = FunctionCall
    <$> genNonEmptyText
    <*> Gen.element ["{}", "{\"arg\": \"value\"}", "{\"count\": 42}"]

genToolCall :: Gen ToolCall
genToolCall = ToolCall
    <$> genToolCallId
    <*> pure "function"
    <*> genFunctionCall

genFunctionCallDelta :: Gen FunctionCallDelta
genFunctionCallDelta = FunctionCallDelta
    <$> Gen.maybe genNonEmptyText
    <*> Gen.maybe genText

genToolCallDelta :: Gen ToolCallDelta
genToolCallDelta = ToolCallDelta
    <$> Gen.int (Range.linear 0 10)
    <*> Gen.maybe genToolCallId
    <*> Gen.maybe (pure "function")
    <*> Gen.maybe genFunctionCallDelta


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // stop sequences
-- ════════════════════════════════════════════════════════════════════════════

genStopSequence :: Gen StopSequence
genStopSequence = Gen.choice
    [ StopSingle <$> genNonEmptyText
    , StopMultiple <$> Gen.list (Range.linear 1 4) genNonEmptyText
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // logit bias
-- ════════════════════════════════════════════════════════════════════════════

genLogitBias :: Gen LogitBias
genLogitBias = do
    -- Generate unique sorted keys for consistent JSON roundtrip
    -- JSON objects don't preserve order, and FromJSON sorts on parse
    n <- Gen.int (Range.linear 0 5)
    keys <- genUniqueSortedTexts n
    vals <- Gen.list (Range.singleton n) (Gen.double (Range.linearFrac (-100) 100))
    pure $ LogitBias (zip keys vals)

-- | Generate n unique non-empty text values, returned in sorted order
genUniqueSortedTexts :: Int -> Gen [Text]
genUniqueSortedTexts n = fmap sort (go n [])
  where
    go 0 acc = pure acc
    go remaining acc = do
        t <- genNonEmptyText
        if t `elem` acc
            then go remaining acc  -- retry with same remaining count
            else go (remaining - 1) (t : acc)
    sort = Data.List.sort


-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // tools
-- ════════════════════════════════════════════════════════════════════════════

genJsonSchema :: Gen JsonSchema
genJsonSchema = JsonSchema <$> genSimpleObject

genSimpleObject :: Gen Object
genSimpleObject = do
    -- Generate a simple JSON schema object
    pure $ KM.fromList
        [ (Key.fromText "type", toJSON ("object" :: Text))
        , (Key.fromText "properties", toJSON (KM.empty :: KM.KeyMap ()))
        ]

genToolFunction :: Gen ToolFunction
genToolFunction = ToolFunction
    <$> genNonEmptyText
    <*> Gen.maybe genText
    <*> Gen.maybe genJsonSchema
    <*> Gen.maybe Gen.bool

genToolDef :: Gen ToolDef
genToolDef = ToolDef
    <$> pure "function"
    <*> genToolFunction


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // tool choice
-- ════════════════════════════════════════════════════════════════════════════

genToolChoiceFunction :: Gen ToolChoiceFunction
genToolChoiceFunction = ToolChoiceFunction <$> genNonEmptyText

genToolChoice :: Gen ToolChoice
genToolChoice = Gen.choice
    [ pure ToolChoiceAuto
    , pure ToolChoiceNone
    , pure ToolChoiceRequired
    , ToolChoiceSpecific <$> pure "function" <*> genToolChoiceFunction
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // response format
-- ════════════════════════════════════════════════════════════════════════════

genResponseFormat :: Gen ResponseFormat
genResponseFormat = Gen.choice
    [ pure ResponseFormatText
    , pure ResponseFormatJsonObject
    , ResponseFormatJsonSchema
        <$> genNonEmptyText
        <*> Gen.maybe genJsonSchema
        <*> Gen.maybe Gen.bool
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // embedding input
-- ════════════════════════════════════════════════════════════════════════════

genEmbeddingInput :: Gen EmbeddingInput
genEmbeddingInput = Gen.choice
    [ EmbeddingText <$> genNonEmptyText
    , EmbeddingTexts <$> Gen.list (Range.linear 1 5) genNonEmptyText
    , EmbeddingTokens <$> Gen.list (Range.linear 1 20) genPositiveInt
    , EmbeddingTokenArrays <$> Gen.list (Range.linear 1 3)
        (Gen.list (Range.linear 1 10) genPositiveInt)
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // messages
-- ════════════════════════════════════════════════════════════════════════════

genContentPart :: Gen ContentPart
genContentPart = Gen.choice
    [ TextPart <$> genNonEmptyText
    , ImageUrlPart <$> genNonEmptyText <*> Gen.maybe (Gen.element ["auto", "low", "high"])
    ]

genMessageContent :: Gen MessageContent
genMessageContent = Gen.choice
    [ TextContent <$> genNonEmptyText
    , PartsContent <$> Gen.list (Range.linear 1 3) genContentPart
    ]

genMessage :: Gen Message
genMessage = do
    role <- genRole
    case role of
        System -> Message role
            <$> (Just <$> genMessageContent)
            <*> Gen.maybe genNonEmptyText
            <*> pure Nothing
            <*> pure Nothing
        User -> Message role
            <$> (Just <$> genMessageContent)
            <*> Gen.maybe genNonEmptyText
            <*> pure Nothing
            <*> pure Nothing
        Assistant -> Gen.choice
            [ Message role
                <$> (Just <$> genMessageContent)
                <*> pure Nothing
                <*> pure Nothing
                <*> pure Nothing
            , Message role
                <$> pure Nothing
                <*> pure Nothing
                <*> pure Nothing
                <*> (Just <$> Gen.list (Range.linear 1 3) genToolCall)
            ]
        Tool -> Message role
            <$> (Just <$> genMessageContent)
            <*> Gen.maybe genNonEmptyText
            <*> (Just <$> genToolCallId)
            <*> pure Nothing


-- ════════════════════════════════════════════════════════════════════════════
--                                                             // delta content
-- ════════════════════════════════════════════════════════════════════════════

genDeltaContent :: Gen DeltaContent
genDeltaContent = DeltaContent
    <$> Gen.maybe genRole
    <*> Gen.maybe genText
    <*> Gen.maybe (Gen.list (Range.linear 1 3) genToolCallDelta)


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // chat completions
-- ════════════════════════════════════════════════════════════════════════════

genUsage :: Gen Usage
genUsage = Usage
    <$> Gen.int (Range.linear 0 10000)
    <*> Gen.int (Range.linear 0 10000)
    <*> Gen.int (Range.linear 0 20000)

genChoice :: Gen Choice
genChoice = Choice
    <$> Gen.int (Range.linear 0 10)
    <*> genMessage
    <*> Gen.maybe genFinishReason

genChoiceDelta :: Gen ChoiceDelta
genChoiceDelta = ChoiceDelta
    <$> Gen.int (Range.linear 0 10)
    <*> Gen.maybe genDeltaContent
    <*> Gen.maybe genFinishReason

genChatRequest :: Gen ChatRequest
genChatRequest = ChatRequest
    <$> genModelId
    <*> Gen.list (Range.linear 1 10) genMessage
    <*> Gen.maybe genTemperature
    <*> Gen.maybe genTopP
    <*> Gen.maybe genPositiveInt
    <*> Gen.maybe Gen.bool
    <*> Gen.maybe genStopSequence
    <*> Gen.maybe genMaxTokens
    <*> Gen.maybe genMaxTokens
    <*> Gen.maybe genDouble
    <*> Gen.maybe genDouble
    <*> Gen.maybe genLogitBias
    <*> Gen.maybe genUserId
    <*> Gen.maybe (Gen.list (Range.linear 1 5) genToolDef)
    <*> Gen.maybe genToolChoice
    <*> Gen.maybe genResponseFormat
    <*> Gen.maybe genInt

genChatResponse :: Gen ChatResponse
genChatResponse = ChatResponse
    <$> genResponseId
    <*> pure "chat.completion"
    <*> genTimestamp
    <*> genModelId
    <*> Gen.list (Range.linear 1 5) genChoice
    <*> Gen.maybe genUsage
    <*> Gen.maybe genNonEmptyText


-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // streaming
-- ════════════════════════════════════════════════════════════════════════════

genStreamChunk :: Gen StreamChunk
genStreamChunk = StreamChunk
    <$> genResponseId
    <*> pure "chat.completion.chunk"
    <*> genTimestamp
    <*> genModelId
    <*> Gen.list (Range.linear 1 5) genChoiceDelta
    <*> Gen.maybe genUsage


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // completions (legacy)
-- ════════════════════════════════════════════════════════════════════════════

genCompletionChoice :: Gen CompletionChoice
genCompletionChoice = CompletionChoice
    <$> genText
    <*> Gen.int (Range.linear 0 10)
    <*> Gen.maybe genFinishReason

genCompletionRequest :: Gen CompletionRequest
genCompletionRequest = CompletionRequest
    <$> genModelId
    <*> genNonEmptyText
    <*> Gen.maybe genMaxTokens
    <*> Gen.maybe genTemperature
    <*> Gen.maybe genTopP
    <*> Gen.maybe genPositiveInt
    <*> Gen.maybe Gen.bool
    <*> Gen.maybe genStopSequence
    <*> Gen.maybe genDouble
    <*> Gen.maybe genDouble
    <*> Gen.maybe genUserId

genCompletionResponse :: Gen CompletionResponse
genCompletionResponse = CompletionResponse
    <$> genResponseId
    <*> pure "text_completion"
    <*> genTimestamp
    <*> genModelId
    <*> Gen.list (Range.linear 1 5) genCompletionChoice
    <*> Gen.maybe genUsage


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // embeddings
-- ════════════════════════════════════════════════════════════════════════════

genEmbeddingData :: Gen EmbeddingData
genEmbeddingData = EmbeddingData
    <$> pure "embedding"
    <*> Gen.int (Range.linear 0 100)
    <*> (V.fromList <$> Gen.list (Range.linear 128 1536)
            (Gen.double (Range.linearFrac (-1.0) 1.0)))

genEmbeddingRequest :: Gen EmbeddingRequest
genEmbeddingRequest = EmbeddingRequest
    <$> genModelId
    <*> genEmbeddingInput
    <*> Gen.maybe genUserId
    <*> Gen.maybe (Gen.element ["float", "base64"])
    <*> Gen.maybe genPositiveInt

genEmbeddingResponse :: Gen EmbeddingResponse
genEmbeddingResponse = EmbeddingResponse
    <$> pure "list"
    <*> Gen.list (Range.linear 1 5) genEmbeddingData
    <*> genModelId
    <*> genUsage


-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // models
-- ════════════════════════════════════════════════════════════════════════════

genModel :: Gen Model
genModel = Model
    <$> genModelId
    <*> pure "model"
    <*> genTimestamp
    <*> Gen.element ["openai", "anthropic", "meta", "google"]

genModelList :: Gen ModelList
genModelList = ModelList
    <$> pure "list"
    <*> Gen.list (Range.linear 1 10) genModel


-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // errors
-- ════════════════════════════════════════════════════════════════════════════

genErrorDetail :: Gen ErrorDetail
genErrorDetail = ErrorDetail
    <$> genNonEmptyText
    <*> Gen.element ["invalid_request_error", "authentication_error", "rate_limit_error", "api_error"]
    <*> Gen.maybe genNonEmptyText
    <*> Gen.maybe genNonEmptyText

genApiError :: Gen ApiError
genApiError = ApiError <$> genErrorDetail
