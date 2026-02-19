-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                             // straylight-llm // type props
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Case heard a throat clearing itself, a phlegmy rasping."
--
--                                                              — Neuromancer
--
-- Property tests for Types.hs JSON serialization. All types must round-trip
-- through JSON encoding and decoding without data loss.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Property.TypesProps
    ( tests
    ) where

import Data.Aeson (decode, encode)
import Hedgehog
import Property.Generators
import Test.Tasty
import Test.Tasty.Hedgehog
import Types


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // semantic types
-- ════════════════════════════════════════════════════════════════════════════

prop_modelIdRoundtrip :: Property
prop_modelIdRoundtrip = property $ do
    x <- forAll genModelId
    decode (encode x) === Just x

prop_temperatureRoundtrip :: Property
prop_temperatureRoundtrip = property $ do
    x <- forAll genTemperature
    decode (encode x) === Just x

prop_topPRoundtrip :: Property
prop_topPRoundtrip = property $ do
    x <- forAll genTopP
    decode (encode x) === Just x

prop_maxTokensRoundtrip :: Property
prop_maxTokensRoundtrip = property $ do
    x <- forAll genMaxTokens
    decode (encode x) === Just x

prop_userIdRoundtrip :: Property
prop_userIdRoundtrip = property $ do
    x <- forAll genUserId
    decode (encode x) === Just x

prop_toolCallIdRoundtrip :: Property
prop_toolCallIdRoundtrip = property $ do
    x <- forAll genToolCallId
    decode (encode x) === Just x

prop_responseIdRoundtrip :: Property
prop_responseIdRoundtrip = property $ do
    x <- forAll genResponseId
    decode (encode x) === Just x

prop_timestampRoundtrip :: Property
prop_timestampRoundtrip = property $ do
    x <- forAll genTimestamp
    decode (encode x) === Just x

prop_finishReasonRoundtrip :: Property
prop_finishReasonRoundtrip = property $ do
    x <- forAll genFinishReason
    decode (encode x) === Just x


-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // roles
-- ════════════════════════════════════════════════════════════════════════════

prop_roleRoundtrip :: Property
prop_roleRoundtrip = property $ do
    x <- forAll genRole
    decode (encode x) === Just x


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // tool calls
-- ════════════════════════════════════════════════════════════════════════════

prop_functionCallRoundtrip :: Property
prop_functionCallRoundtrip = property $ do
    x <- forAll genFunctionCall
    decode (encode x) === Just x

prop_toolCallRoundtrip :: Property
prop_toolCallRoundtrip = property $ do
    x <- forAll genToolCall
    decode (encode x) === Just x

prop_functionCallDeltaRoundtrip :: Property
prop_functionCallDeltaRoundtrip = property $ do
    x <- forAll genFunctionCallDelta
    decode (encode x) === Just x

prop_toolCallDeltaRoundtrip :: Property
prop_toolCallDeltaRoundtrip = property $ do
    x <- forAll genToolCallDelta
    decode (encode x) === Just x


-- ════════════════════════════════════════════════════════════════════════════
--                                                         // request parameters
-- ════════════════════════════════════════════════════════════════════════════

prop_stopSequenceRoundtrip :: Property
prop_stopSequenceRoundtrip = property $ do
    x <- forAll genStopSequence
    decode (encode x) === Just x

prop_logitBiasRoundtrip :: Property
prop_logitBiasRoundtrip = property $ do
    x <- forAll genLogitBias
    decode (encode x) === Just x

prop_toolDefRoundtrip :: Property
prop_toolDefRoundtrip = property $ do
    x <- forAll genToolDef
    decode (encode x) === Just x

prop_toolFunctionRoundtrip :: Property
prop_toolFunctionRoundtrip = property $ do
    x <- forAll genToolFunction
    decode (encode x) === Just x

prop_toolChoiceRoundtrip :: Property
prop_toolChoiceRoundtrip = property $ do
    x <- forAll genToolChoice
    decode (encode x) === Just x

prop_responseFormatRoundtrip :: Property
prop_responseFormatRoundtrip = property $ do
    x <- forAll genResponseFormat
    decode (encode x) === Just x

prop_embeddingInputRoundtrip :: Property
prop_embeddingInputRoundtrip = property $ do
    x <- forAll genEmbeddingInput
    decode (encode x) === Just x

prop_deltaContentRoundtrip :: Property
prop_deltaContentRoundtrip = property $ do
    x <- forAll genDeltaContent
    decode (encode x) === Just x


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // messages
-- ════════════════════════════════════════════════════════════════════════════

prop_contentPartRoundtrip :: Property
prop_contentPartRoundtrip = property $ do
    x <- forAll genContentPart
    decode (encode x) === Just x

prop_messageContentRoundtrip :: Property
prop_messageContentRoundtrip = property $ do
    x <- forAll genMessageContent
    decode (encode x) === Just x

prop_messageRoundtrip :: Property
prop_messageRoundtrip = property $ do
    x <- forAll genMessage
    decode (encode x) === Just x


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // chat completions
-- ════════════════════════════════════════════════════════════════════════════

prop_usageRoundtrip :: Property
prop_usageRoundtrip = property $ do
    x <- forAll genUsage
    decode (encode x) === Just x

prop_choiceRoundtrip :: Property
prop_choiceRoundtrip = property $ do
    x <- forAll genChoice
    decode (encode x) === Just x

prop_choiceDeltaRoundtrip :: Property
prop_choiceDeltaRoundtrip = property $ do
    x <- forAll genChoiceDelta
    decode (encode x) === Just x

prop_chatRequestRoundtrip :: Property
prop_chatRequestRoundtrip = property $ do
    x <- forAll genChatRequest
    decode (encode x) === Just x

prop_chatResponseRoundtrip :: Property
prop_chatResponseRoundtrip = property $ do
    x <- forAll genChatResponse
    decode (encode x) === Just x


-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // streaming
-- ════════════════════════════════════════════════════════════════════════════

prop_streamChunkRoundtrip :: Property
prop_streamChunkRoundtrip = property $ do
    x <- forAll genStreamChunk
    decode (encode x) === Just x


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // completions (legacy)
-- ════════════════════════════════════════════════════════════════════════════

prop_completionChoiceRoundtrip :: Property
prop_completionChoiceRoundtrip = property $ do
    x <- forAll genCompletionChoice
    decode (encode x) === Just x

prop_completionRequestRoundtrip :: Property
prop_completionRequestRoundtrip = property $ do
    x <- forAll genCompletionRequest
    decode (encode x) === Just x

prop_completionResponseRoundtrip :: Property
prop_completionResponseRoundtrip = property $ do
    x <- forAll genCompletionResponse
    decode (encode x) === Just x


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // embeddings
-- ════════════════════════════════════════════════════════════════════════════

prop_embeddingDataRoundtrip :: Property
prop_embeddingDataRoundtrip = property $ do
    x <- forAll genEmbeddingData
    decode (encode x) === Just x

prop_embeddingRequestRoundtrip :: Property
prop_embeddingRequestRoundtrip = property $ do
    x <- forAll genEmbeddingRequest
    decode (encode x) === Just x

prop_embeddingResponseRoundtrip :: Property
prop_embeddingResponseRoundtrip = property $ do
    x <- forAll genEmbeddingResponse
    decode (encode x) === Just x


-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // models
-- ════════════════════════════════════════════════════════════════════════════

prop_modelRoundtrip :: Property
prop_modelRoundtrip = property $ do
    x <- forAll genModel
    decode (encode x) === Just x

prop_modelListRoundtrip :: Property
prop_modelListRoundtrip = property $ do
    x <- forAll genModelList
    decode (encode x) === Just x


-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // errors
-- ════════════════════════════════════════════════════════════════════════════

prop_errorDetailRoundtrip :: Property
prop_errorDetailRoundtrip = property $ do
    x <- forAll genErrorDetail
    decode (encode x) === Just x

prop_apiErrorRoundtrip :: Property
prop_apiErrorRoundtrip = property $ do
    x <- forAll genApiError
    decode (encode x) === Just x


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "Types Property Tests"
    [ testGroup "Semantic Types"
        [ testProperty "ModelId round-trip" prop_modelIdRoundtrip
        , testProperty "Temperature round-trip" prop_temperatureRoundtrip
        , testProperty "TopP round-trip" prop_topPRoundtrip
        , testProperty "MaxTokens round-trip" prop_maxTokensRoundtrip
        , testProperty "UserId round-trip" prop_userIdRoundtrip
        , testProperty "ToolCallId round-trip" prop_toolCallIdRoundtrip
        , testProperty "ResponseId round-trip" prop_responseIdRoundtrip
        , testProperty "Timestamp round-trip" prop_timestampRoundtrip
        , testProperty "FinishReason round-trip" prop_finishReasonRoundtrip
        ]
    , testGroup "Roles"
        [ testProperty "Role round-trip" prop_roleRoundtrip
        ]
    , testGroup "Tool Calls"
        [ testProperty "FunctionCall round-trip" prop_functionCallRoundtrip
        , testProperty "ToolCall round-trip" prop_toolCallRoundtrip
        , testProperty "FunctionCallDelta round-trip" prop_functionCallDeltaRoundtrip
        , testProperty "ToolCallDelta round-trip" prop_toolCallDeltaRoundtrip
        ]
    , testGroup "Request Parameters"
        [ testProperty "StopSequence round-trip" prop_stopSequenceRoundtrip
        , testProperty "LogitBias round-trip" prop_logitBiasRoundtrip
        , testProperty "ToolDef round-trip" prop_toolDefRoundtrip
        , testProperty "ToolFunction round-trip" prop_toolFunctionRoundtrip
        , testProperty "ToolChoice round-trip" prop_toolChoiceRoundtrip
        , testProperty "ResponseFormat round-trip" prop_responseFormatRoundtrip
        , testProperty "EmbeddingInput round-trip" prop_embeddingInputRoundtrip
        , testProperty "DeltaContent round-trip" prop_deltaContentRoundtrip
        ]
    , testGroup "Messages"
        [ testProperty "ContentPart round-trip" prop_contentPartRoundtrip
        , testProperty "MessageContent round-trip" prop_messageContentRoundtrip
        , testProperty "Message round-trip" prop_messageRoundtrip
        ]
    , testGroup "Chat Completions"
        [ testProperty "Usage round-trip" prop_usageRoundtrip
        , testProperty "Choice round-trip" prop_choiceRoundtrip
        , testProperty "ChoiceDelta round-trip" prop_choiceDeltaRoundtrip
        , testProperty "ChatRequest round-trip" prop_chatRequestRoundtrip
        , testProperty "ChatResponse round-trip" prop_chatResponseRoundtrip
        ]
    , testGroup "Streaming"
        [ testProperty "StreamChunk round-trip" prop_streamChunkRoundtrip
        ]
    , testGroup "Completions (Legacy)"
        [ testProperty "CompletionChoice round-trip" prop_completionChoiceRoundtrip
        , testProperty "CompletionRequest round-trip" prop_completionRequestRoundtrip
        , testProperty "CompletionResponse round-trip" prop_completionResponseRoundtrip
        ]
    , testGroup "Embeddings"
        [ testProperty "EmbeddingData round-trip" prop_embeddingDataRoundtrip
        , testProperty "EmbeddingRequest round-trip" prop_embeddingRequestRoundtrip
        , testProperty "EmbeddingResponse round-trip" prop_embeddingResponseRoundtrip
        ]
    , testGroup "Models"
        [ testProperty "Model round-trip" prop_modelRoundtrip
        , testProperty "ModelList round-trip" prop_modelListRoundtrip
        ]
    , testGroup "Errors"
        [ testProperty "ErrorDetail round-trip" prop_errorDetailRoundtrip
        , testProperty "ApiError round-trip" prop_apiErrorRoundtrip
        ]
    ]
