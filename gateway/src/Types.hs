-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                   // straylight-llm // types
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "A year here and he still dreamed of cyberspace, hope fading nightly."
--
--                                                              — Neuromancer
--
-- OpenAI-compatible request/response types for the LLM gateway proxy.
-- All providers (Venice, Vertex, Baseten, OpenAI) speak this format.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Types
    ( -- * Semantic Types
      ModelId (..)
    , Temperature (..)
    , TopP (..)
    , MaxTokens (..)
    , UserId (..)
    , ToolCallId (..)
    , ResponseId (..)
    , Timestamp (..)
    , FinishReason (..)

      -- * Messages
    , Message (..)
    , Role (..)
    , ContentPart (..)
    , MessageContent (..)

      -- * Tool Calls
    , ToolCall (..)
    , FunctionCall (..)
    , ToolCallDelta (..)
    , FunctionCallDelta (..)

      -- * Request Parameters
    , StopSequence (..)
    , LogitBias (..)
    , ToolDef (..)
    , ToolFunction (..)
    , JsonSchema (..)
    , ToolChoice (..)
    , ToolChoiceFunction (..)
    , ResponseFormat (..)
    , EmbeddingInput (..)
    , DeltaContent (..)

      -- * Chat Completions
    , ChatRequest (..)
    , ChatResponse (..)
    , Choice (..)
    , ChoiceDelta (..)
    , Usage (..)

      -- * Completions (legacy)
    , CompletionRequest (..)
    , CompletionResponse (..)
    , CompletionChoice (..)

      -- * Embeddings
    , EmbeddingRequest (..)
    , EmbeddingResponse (..)
    , EmbeddingData (..)

      -- * Models
    , Model (..)
    , ModelList (..)

      -- * Streaming
    , StreamChunk (..)

      -- * Errors
    , ApiError (..)
    , ErrorDetail (..)
    ) where

import Data.Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap (foldrWithKey)
import Data.Text (Text)
import Data.Vector (Vector)
import GHC.Generics (Generic)


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // semantic types
-- ════════════════════════════════════════════════════════════════════════════

{- | Model identifier (e.g. "gpt-4", "claude-3-opus").

Prevents accidental mixing with other Text values.
-}
newtype ModelId = ModelId {unModelId :: Text}
    deriving stock (Eq, Ord, Show, Generic)
    deriving newtype (ToJSON, FromJSON)

{- | Sampling temperature (0.0 to 2.0).

Controls randomness in token selection. Higher values produce more random output.
-}
newtype Temperature = Temperature {unTemperature :: Double}
    deriving stock (Eq, Ord, Show, Generic)
    deriving newtype (ToJSON, FromJSON)

{- | Top-p sampling parameter (0.0 to 1.0).

Also known as nucleus sampling. Limits token selection to a cumulative probability.
-}
newtype TopP = TopP {unTopP :: Double}
    deriving stock (Eq, Ord, Show, Generic)
    deriving newtype (ToJSON, FromJSON)

{- | Maximum tokens for completion.

Limits the number of tokens in the generated response.
-}
newtype MaxTokens = MaxTokens {unMaxTokens :: Int}
    deriving stock (Eq, Ord, Show, Generic)
    deriving newtype (ToJSON, FromJSON)

{- | User identifier for tracking and abuse prevention.

Passed through to the upstream provider for rate limiting.
-}
newtype UserId = UserId {unUserId :: Text}
    deriving stock (Eq, Ord, Show, Generic)
    deriving newtype (ToJSON, FromJSON)

{- | Tool call identifier.

Unique identifier for a tool invocation within a message.
-}
newtype ToolCallId = ToolCallId {unToolCallId :: Text}
    deriving stock (Eq, Ord, Show, Generic)
    deriving newtype (ToJSON, FromJSON)

{- | Response identifier.

Unique identifier for a completion response.
-}
newtype ResponseId = ResponseId {unResponseId :: Text}
    deriving stock (Eq, Ord, Show, Generic)
    deriving newtype (ToJSON, FromJSON)

{- | Unix timestamp.

Seconds since epoch (1970-01-01 00:00:00 UTC).
-}
newtype Timestamp = Timestamp {unTimestamp :: Int}
    deriving stock (Eq, Ord, Show, Generic)
    deriving newtype (ToJSON, FromJSON)

{- | Finish reason (e.g. "stop", "length", "tool_calls").

Indicates why the model stopped generating tokens.
-}
newtype FinishReason = FinishReason {unFinishReason :: Text}
    deriving stock (Eq, Ord, Show, Generic)
    deriving newtype (ToJSON, FromJSON)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // roles
-- ════════════════════════════════════════════════════════════════════════════

data Role = System | User | Assistant | Tool
    deriving stock (Eq, Show, Generic)

instance ToJSON Role where
    toJSON = \case
        System -> "system"
        User -> "user"
        Assistant -> "assistant"
        Tool -> "tool"

instance FromJSON Role where
    parseJSON = withText "Role" $ \case
        "system" -> pure System
        "user" -> pure User
        "assistant" -> pure Assistant
        "tool" -> pure Tool
        other -> fail $ "Unknown role: " <> show other


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // tool calls
-- ════════════════════════════════════════════════════════════════════════════

-- | Function call within a tool call
data FunctionCall = FunctionCall
    { fcName :: Text
    , fcArguments :: Text  -- JSON string of arguments
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON FunctionCall where
    toJSON FunctionCall{..} = object
        [ "name" .= fcName
        , "arguments" .= fcArguments
        ]

instance FromJSON FunctionCall where
    parseJSON = withObject "FunctionCall" $ \v ->
        FunctionCall
            <$> v .: "name"
            <*> v .:? "arguments" .!= ""

-- | Tool call from assistant message
data ToolCall = ToolCall
    { tcId :: ToolCallId
    , tcType :: Text       -- Currently always "function"
    , tcFunction :: FunctionCall
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ToolCall where
    toJSON ToolCall{..} = object
        [ "id" .= tcId
        , "type" .= tcType
        , "function" .= tcFunction
        ]

instance FromJSON ToolCall where
    parseJSON = withObject "ToolCall" $ \v ->
        ToolCall
            <$> v .: "id"
            <*> v .:? "type" .!= "function"
            <*> v .: "function"


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // stop sequences
-- ════════════════════════════════════════════════════════════════════════════

-- | Stop sequence: either a single string or a list of strings
data StopSequence
    = StopSingle Text
    | StopMultiple [Text]
    deriving stock (Eq, Show, Generic)

instance ToJSON StopSequence where
    toJSON (StopSingle t) = toJSON t
    toJSON (StopMultiple ts) = toJSON ts

instance FromJSON StopSequence where
    parseJSON (String t) = pure $ StopSingle t
    parseJSON (Array a) = StopMultiple <$> mapM parseJSON (foldr (:) [] a)
    parseJSON _ = fail "Stop must be string or array of strings"


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // logit bias
-- ════════════════════════════════════════════════════════════════════════════

-- | Logit bias: map from token ID to bias value (-100 to 100)
newtype LogitBias = LogitBias { unLogitBias :: [(Text, Double)] }
    deriving stock (Eq, Show, Generic)

instance ToJSON LogitBias where
    toJSON (LogitBias biases) = object [(Key.fromText k, toJSON v) | (k, v) <- biases]

instance FromJSON LogitBias where
    parseJSON = withObject "LogitBias" $ \v ->
        LogitBias <$> mapM (\(k, val) -> (Key.toText k,) <$> parseJSON val) (toList v)
      where
        toList obj = foldrWithKey (\k val acc -> (k, val) : acc) [] obj


-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // tools
-- ════════════════════════════════════════════════════════════════════════════

-- | JSON Schema for tool parameters (simplified - we preserve the structure)
newtype JsonSchema = JsonSchema { unJsonSchema :: Object }
    deriving stock (Eq, Show, Generic)

instance ToJSON JsonSchema where
    toJSON (JsonSchema obj) = Object obj

instance FromJSON JsonSchema where
    parseJSON = withObject "JsonSchema" $ pure . JsonSchema

-- | Tool function definition
data ToolFunction = ToolFunction
    { tfName :: Text
    , tfDescription :: Maybe Text
    , tfParameters :: Maybe JsonSchema
    , tfStrict :: Maybe Bool
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ToolFunction where
    toJSON ToolFunction{..} = object $ filter ((/= Null) . snd)
        [ "name" .= tfName
        , "description" .= tfDescription
        , "parameters" .= tfParameters
        , "strict" .= tfStrict
        ]

instance FromJSON ToolFunction where
    parseJSON = withObject "ToolFunction" $ \v ->
        ToolFunction
            <$> v .: "name"
            <*> v .:? "description"
            <*> v .:? "parameters"
            <*> v .:? "strict"

-- | Tool definition
data ToolDef = ToolDef
    { toolType :: Text      -- Currently always "function"
    , toolFunction :: ToolFunction
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ToolDef where
    toJSON ToolDef{..} = object
        [ "type" .= toolType
        , "function" .= toolFunction
        ]

instance FromJSON ToolDef where
    parseJSON = withObject "ToolDef" $ \v ->
        ToolDef
            <$> v .:? "type" .!= "function"
            <*> v .: "function"


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // tool choice
-- ════════════════════════════════════════════════════════════════════════════

-- | Specific function for tool_choice
data ToolChoiceFunction = ToolChoiceFunction
    { tcfName :: Text
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ToolChoiceFunction where
    toJSON ToolChoiceFunction{..} = object ["name" .= tcfName]

instance FromJSON ToolChoiceFunction where
    parseJSON = withObject "ToolChoiceFunction" $ \v ->
        ToolChoiceFunction <$> v .: "name"

-- | Tool choice: "auto", "none", "required", or specific function
data ToolChoice
    = ToolChoiceAuto
    | ToolChoiceNone
    | ToolChoiceRequired
    | ToolChoiceSpecific Text ToolChoiceFunction  -- type and function
    deriving stock (Eq, Show, Generic)

instance ToJSON ToolChoice where
    toJSON ToolChoiceAuto = "auto"
    toJSON ToolChoiceNone = "none"
    toJSON ToolChoiceRequired = "required"
    toJSON (ToolChoiceSpecific typ func) = object
        [ "type" .= typ
        , "function" .= func
        ]

instance FromJSON ToolChoice where
    parseJSON (String "auto") = pure ToolChoiceAuto
    parseJSON (String "none") = pure ToolChoiceNone
    parseJSON (String "required") = pure ToolChoiceRequired
    parseJSON (Object v) =
        ToolChoiceSpecific
            <$> v .:? "type" .!= "function"
            <*> v .: "function"
    parseJSON _ = fail "tool_choice must be string or object"


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // response format
-- ════════════════════════════════════════════════════════════════════════════

-- | Response format type
data ResponseFormat
    = ResponseFormatText
    | ResponseFormatJsonObject
    | ResponseFormatJsonSchema Text (Maybe JsonSchema) (Maybe Bool) -- name, schema, strict
    deriving stock (Eq, Show, Generic)

instance ToJSON ResponseFormat where
    toJSON ResponseFormatText = object ["type" .= ("text" :: Text)]
    toJSON ResponseFormatJsonObject = object ["type" .= ("json_object" :: Text)]
    toJSON (ResponseFormatJsonSchema name mSchema mStrict) = object $ filter ((/= Null) . snd)
        [ "type" .= ("json_schema" :: Text)
        , "json_schema" .= object (filter ((/= Null) . snd)
            [ "name" .= name
            , "schema" .= mSchema
            , "strict" .= mStrict
            ])
        ]

instance FromJSON ResponseFormat where
    parseJSON = withObject "ResponseFormat" $ \v -> do
        typ <- v .: "type"
        case typ :: Text of
            "text" -> pure ResponseFormatText
            "json_object" -> pure ResponseFormatJsonObject
            "json_schema" -> do
                schemaObj <- v .: "json_schema"
                name <- schemaObj .: "name"
                schema <- schemaObj .:? "schema"
                strict <- schemaObj .:? "strict"
                pure $ ResponseFormatJsonSchema name schema strict
            other -> fail $ "Unknown response_format type: " <> show other


-- ════════════════════════════════════════════════════════════════════════════
--                                                             // delta content
-- ════════════════════════════════════════════════════════════════════════════

-- | Delta content in streaming response
data DeltaContent = DeltaContent
    { dcRole :: Maybe Role
    , dcContent :: Maybe Text
    , dcToolCalls :: Maybe [ToolCallDelta]
    }
    deriving stock (Eq, Show, Generic)

-- | Tool call delta in streaming (may have partial data)
data ToolCallDelta = ToolCallDelta
    { tcdIndex :: Int
    , tcdId :: Maybe ToolCallId
    , tcdType :: Maybe Text
    , tcdFunction :: Maybe FunctionCallDelta
    }
    deriving stock (Eq, Show, Generic)

-- | Function call delta in streaming
data FunctionCallDelta = FunctionCallDelta
    { fcdName :: Maybe Text
    , fcdArguments :: Maybe Text
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON FunctionCallDelta where
    toJSON FunctionCallDelta{..} = object $ filter ((/= Null) . snd)
        [ "name" .= fcdName
        , "arguments" .= fcdArguments
        ]

instance FromJSON FunctionCallDelta where
    parseJSON = withObject "FunctionCallDelta" $ \v ->
        FunctionCallDelta
            <$> v .:? "name"
            <*> v .:? "arguments"

instance ToJSON ToolCallDelta where
    toJSON ToolCallDelta{..} = object $ filter ((/= Null) . snd)
        [ "index" .= tcdIndex
        , "id" .= tcdId
        , "type" .= tcdType
        , "function" .= tcdFunction
        ]

instance FromJSON ToolCallDelta where
    parseJSON = withObject "ToolCallDelta" $ \v ->
        ToolCallDelta
            <$> v .: "index"
            <*> v .:? "id"
            <*> v .:? "type"
            <*> v .:? "function"

instance ToJSON DeltaContent where
    toJSON DeltaContent{..} = object $ filter ((/= Null) . snd)
        [ "role" .= dcRole
        , "content" .= dcContent
        , "tool_calls" .= dcToolCalls
        ]

instance FromJSON DeltaContent where
    parseJSON = withObject "DeltaContent" $ \v ->
        DeltaContent
            <$> v .:? "role"
            <*> v .:? "content"
            <*> v .:? "tool_calls"


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // embedding input
-- ════════════════════════════════════════════════════════════════════════════

-- | Embedding input: single string, array of strings, array of tokens, or array of token arrays
data EmbeddingInput
    = EmbeddingText Text
    | EmbeddingTexts [Text]
    | EmbeddingTokens [Int]
    | EmbeddingTokenArrays [[Int]]
    deriving stock (Eq, Show, Generic)

instance ToJSON EmbeddingInput where
    toJSON (EmbeddingText t) = toJSON t
    toJSON (EmbeddingTexts ts) = toJSON ts
    toJSON (EmbeddingTokens tokens) = toJSON tokens
    toJSON (EmbeddingTokenArrays arrays) = toJSON arrays

instance FromJSON EmbeddingInput where
    parseJSON (String t) = pure $ EmbeddingText t
    parseJSON (Array a) = do
        let items = foldr (:) [] a
        case items of
            [] -> pure $ EmbeddingTexts []
            (x:_) -> case x of
                String _ -> EmbeddingTexts <$> mapM parseJSON items
                Number _ -> EmbeddingTokens <$> mapM parseJSON items
                Array _ -> EmbeddingTokenArrays <$> mapM parseJSON items
                _ -> fail "Embedding input array must contain strings, numbers, or arrays"
    parseJSON _ = fail "Embedding input must be string or array"


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // messages
-- ════════════════════════════════════════════════════════════════════════════

-- | Content can be text or multimodal (text + images)
data ContentPart
    = TextPart Text
    | ImageUrlPart Text (Maybe Text)  -- url, optional detail level
    deriving stock (Eq, Show, Generic)

instance ToJSON ContentPart where
    toJSON (TextPart t) = object ["type" .= ("text" :: Text), "text" .= t]
    toJSON (ImageUrlPart url detail) = object $
        [ "type" .= ("image_url" :: Text)
        , "image_url" .= object (["url" .= url] <> maybe [] (\d -> ["detail" .= d]) detail)
        ]

instance FromJSON ContentPart where
    parseJSON = withObject "ContentPart" $ \v -> do
        typ <- v .: "type"
        case typ :: Text of
            "text" -> TextPart <$> v .: "text"
            "image_url" -> do
                imgObj <- v .: "image_url"
                url <- imgObj .: "url"
                detail <- imgObj .:? "detail"
                pure $ ImageUrlPart url detail
            _ -> fail "Unknown content part type"

-- | Message content: either simple text or array of parts
data MessageContent
    = TextContent Text
    | PartsContent [ContentPart]
    deriving stock (Eq, Show, Generic)

instance ToJSON MessageContent where
    toJSON (TextContent t) = toJSON t
    toJSON (PartsContent ps) = toJSON ps

instance FromJSON MessageContent where
    parseJSON (String t) = pure $ TextContent t
    parseJSON (Array a) = PartsContent <$> mapM parseJSON (foldr (:) [] a)
    parseJSON _ = fail "Content must be string or array"

-- | Chat message
data Message = Message
    { msgRole :: Role
    , msgContent :: Maybe MessageContent  -- Nothing for tool_calls-only messages
    , msgName :: Maybe Text               -- For tool messages
    , msgToolCallId :: Maybe ToolCallId   -- For tool result messages
    , msgToolCalls :: Maybe [ToolCall]    -- Tool calls from assistant
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON Message where
    toJSON Message{..} = object $ filter ((/= Null) . snd)
        [ "role" .= msgRole
        , "content" .= msgContent
        , "name" .= msgName
        , "tool_call_id" .= msgToolCallId
        , "tool_calls" .= msgToolCalls
        ]

instance FromJSON Message where
    parseJSON = withObject "Message" $ \v ->
        Message
            <$> v .: "role"
            <*> v .:? "content"
            <*> v .:? "name"
            <*> v .:? "tool_call_id"
            <*> v .:? "tool_calls"


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // chat completions
-- ════════════════════════════════════════════════════════════════════════════

-- | Chat completion request (OpenAI format)
data ChatRequest = ChatRequest
    { crModel :: ModelId
    , crMessages :: [Message]
    , crTemperature :: Maybe Temperature
    , crTopP :: Maybe TopP
    , crN :: Maybe Int
    , crStream :: Maybe Bool
    , crStop :: Maybe StopSequence
    , crMaxTokens :: Maybe MaxTokens
    , crMaxCompletionTokens :: Maybe MaxTokens -- OpenAI's newer field
    , crPresencePenalty :: Maybe Double
    , crFrequencyPenalty :: Maybe Double
    , crLogitBias :: Maybe LogitBias
    , crUser :: Maybe UserId
    , crTools :: Maybe [ToolDef]
    , crToolChoice :: Maybe ToolChoice
    , crResponseFormat :: Maybe ResponseFormat
    , crSeed :: Maybe Int
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ChatRequest where
    toJSON ChatRequest{..} = object $ filter ((/= Null) . snd)
        [ "model" .= crModel
        , "messages" .= crMessages
        , "temperature" .= crTemperature
        , "top_p" .= crTopP
        , "n" .= crN
        , "stream" .= crStream
        , "stop" .= crStop
        , "max_tokens" .= crMaxTokens
        , "max_completion_tokens" .= crMaxCompletionTokens
        , "presence_penalty" .= crPresencePenalty
        , "frequency_penalty" .= crFrequencyPenalty
        , "logit_bias" .= crLogitBias
        , "user" .= crUser
        , "tools" .= crTools
        , "tool_choice" .= crToolChoice
        , "response_format" .= crResponseFormat
        , "seed" .= crSeed
        ]

instance FromJSON ChatRequest where
    parseJSON = withObject "ChatRequest" $ \v ->
        ChatRequest
            <$> v .: "model"
            <*> v .: "messages"
            <*> v .:? "temperature"
            <*> v .:? "top_p"
            <*> v .:? "n"
            <*> v .:? "stream"
            <*> v .:? "stop"
            <*> v .:? "max_tokens"
            <*> v .:? "max_completion_tokens"
            <*> v .:? "presence_penalty"
            <*> v .:? "frequency_penalty"
            <*> v .:? "logit_bias"
            <*> v .:? "user"
            <*> v .:? "tools"
            <*> v .:? "tool_choice"
            <*> v .:? "response_format"
            <*> v .:? "seed"

-- | Token usage statistics
data Usage = Usage
    { usagePromptTokens :: Int
    , usageCompletionTokens :: Int
    , usageTotalTokens :: Int
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON Usage where
    toJSON Usage{..} = object
        [ "prompt_tokens" .= usagePromptTokens
        , "completion_tokens" .= usageCompletionTokens
        , "total_tokens" .= usageTotalTokens
        ]

instance FromJSON Usage where
    parseJSON = withObject "Usage" $ \v ->
        Usage
            <$> v .:? "prompt_tokens" .!= 0
            <*> v .:? "completion_tokens" .!= 0
            <*> v .:? "total_tokens" .!= 0

-- | Choice in chat completion response
data Choice = Choice
    { choiceIndex :: Int
    , choiceMessage :: Message
    , choiceFinishReason :: Maybe FinishReason
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON Choice where
    toJSON Choice{..} = object
        [ "index" .= choiceIndex
        , "message" .= choiceMessage
        , "finish_reason" .= choiceFinishReason
        ]

instance FromJSON Choice where
    parseJSON = withObject "Choice" $ \v ->
        Choice
            <$> v .: "index"
            <*> v .: "message"
            <*> v .:? "finish_reason"

-- | Chat completion response
data ChatResponse = ChatResponse
    { respId :: ResponseId
    , respObject :: Text           -- "chat.completion"
    , respCreated :: Timestamp
    , respModel :: ModelId
    , respChoices :: [Choice]
    , respUsage :: Maybe Usage
    , respSystemFingerprint :: Maybe Text
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ChatResponse where
    toJSON ChatResponse{..} = object $ filter ((/= Null) . snd)
        [ "id" .= respId
        , "object" .= respObject
        , "created" .= respCreated
        , "model" .= respModel
        , "choices" .= respChoices
        , "usage" .= respUsage
        , "system_fingerprint" .= respSystemFingerprint
        ]

instance FromJSON ChatResponse where
    parseJSON = withObject "ChatResponse" $ \v ->
        ChatResponse
            <$> v .: "id"
            <*> v .:? "object" .!= "chat.completion"
            <*> v .:? "created" .!= Timestamp 0
            <*> v .: "model"
            <*> v .: "choices"
            <*> v .:? "usage"
            <*> v .:? "system_fingerprint"


-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // streaming
-- ════════════════════════════════════════════════════════════════════════════

-- | Delta in streaming response
data ChoiceDelta = ChoiceDelta
    { deltaIndex :: Int
    , deltaDelta :: Maybe DeltaContent
    , deltaFinishReason :: Maybe FinishReason
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ChoiceDelta where
    toJSON ChoiceDelta{..} = object $ filter ((/= Null) . snd)
        [ "index" .= deltaIndex
        , "delta" .= deltaDelta
        , "finish_reason" .= deltaFinishReason
        ]

instance FromJSON ChoiceDelta where
    parseJSON = withObject "ChoiceDelta" $ \v ->
        ChoiceDelta
            <$> v .: "index"
            <*> v .:? "delta"
            <*> v .:? "finish_reason"

-- | Streaming chunk
data StreamChunk = StreamChunk
    { chunkId :: ResponseId
    , chunkObject :: Text          -- "chat.completion.chunk"
    , chunkCreated :: Timestamp
    , chunkModel :: ModelId
    , chunkChoices :: [ChoiceDelta]
    , chunkUsage :: Maybe Usage    -- Only in final chunk with stream_options
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON StreamChunk where
    toJSON StreamChunk{..} = object $ filter ((/= Null) . snd)
        [ "id" .= chunkId
        , "object" .= chunkObject
        , "created" .= chunkCreated
        , "model" .= chunkModel
        , "choices" .= chunkChoices
        , "usage" .= chunkUsage
        ]

instance FromJSON StreamChunk where
    parseJSON = withObject "StreamChunk" $ \v ->
        StreamChunk
            <$> v .: "id"
            <*> v .:? "object" .!= "chat.completion.chunk"
            <*> v .:? "created" .!= Timestamp 0
            <*> v .: "model"
            <*> v .: "choices"
            <*> v .:? "usage"


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // completions (legacy)
-- ════════════════════════════════════════════════════════════════════════════

-- | Legacy completion request
data CompletionRequest = CompletionRequest
    { complModel :: ModelId
    , complPrompt :: Text
    , complMaxTokens :: Maybe MaxTokens
    , complTemperature :: Maybe Temperature
    , complTopP :: Maybe TopP
    , complN :: Maybe Int
    , complStream :: Maybe Bool
    , complStop :: Maybe StopSequence
    , complPresencePenalty :: Maybe Double
    , complFrequencyPenalty :: Maybe Double
    , complUser :: Maybe UserId
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON CompletionRequest where
    toJSON CompletionRequest{..} = object $ filter ((/= Null) . snd)
        [ "model" .= complModel
        , "prompt" .= complPrompt
        , "max_tokens" .= complMaxTokens
        , "temperature" .= complTemperature
        , "top_p" .= complTopP
        , "n" .= complN
        , "stream" .= complStream
        , "stop" .= complStop
        , "presence_penalty" .= complPresencePenalty
        , "frequency_penalty" .= complFrequencyPenalty
        , "user" .= complUser
        ]

instance FromJSON CompletionRequest where
    parseJSON = withObject "CompletionRequest" $ \v ->
        CompletionRequest
            <$> v .: "model"
            <*> v .: "prompt"
            <*> v .:? "max_tokens"
            <*> v .:? "temperature"
            <*> v .:? "top_p"
            <*> v .:? "n"
            <*> v .:? "stream"
            <*> v .:? "stop"
            <*> v .:? "presence_penalty"
            <*> v .:? "frequency_penalty"
            <*> v .:? "user"

-- | Legacy completion choice
data CompletionChoice = CompletionChoice
    { ccText :: Text
    , ccIndex :: Int
    , ccFinishReason :: Maybe FinishReason
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON CompletionChoice where
    toJSON CompletionChoice{..} = object
        [ "text" .= ccText
        , "index" .= ccIndex
        , "finish_reason" .= ccFinishReason
        ]

instance FromJSON CompletionChoice where
    parseJSON = withObject "CompletionChoice" $ \v ->
        CompletionChoice
            <$> v .: "text"
            <*> v .: "index"
            <*> v .:? "finish_reason"

-- | Legacy completion response
data CompletionResponse = CompletionResponse
    { complRespId :: ResponseId
    , complRespObject :: Text
    , complRespCreated :: Timestamp
    , complRespModel :: ModelId
    , complRespChoices :: [CompletionChoice]
    , complRespUsage :: Maybe Usage
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON CompletionResponse where
    toJSON CompletionResponse{..} = object
        [ "id" .= complRespId
        , "object" .= complRespObject
        , "created" .= complRespCreated
        , "model" .= complRespModel
        , "choices" .= complRespChoices
        , "usage" .= complRespUsage
        ]

instance FromJSON CompletionResponse where
    parseJSON = withObject "CompletionResponse" $ \v ->
        CompletionResponse
            <$> v .: "id"
            <*> v .:? "object" .!= "text_completion"
            <*> v .:? "created" .!= Timestamp 0
            <*> v .: "model"
            <*> v .: "choices"
            <*> v .:? "usage"


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // embeddings
-- ════════════════════════════════════════════════════════════════════════════

-- | Embedding request
data EmbeddingRequest = EmbeddingRequest
    { embModel :: ModelId
    , embInput :: EmbeddingInput
    , embUser :: Maybe UserId
    , embEncodingFormat :: Maybe Text  -- "float" or "base64"
    , embDimensions :: Maybe Int
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON EmbeddingRequest where
    toJSON EmbeddingRequest{..} = object $ filter ((/= Null) . snd)
        [ "model" .= embModel
        , "input" .= embInput
        , "user" .= embUser
        , "encoding_format" .= embEncodingFormat
        , "dimensions" .= embDimensions
        ]

instance FromJSON EmbeddingRequest where
    parseJSON = withObject "EmbeddingRequest" $ \v ->
        EmbeddingRequest
            <$> v .: "model"
            <*> v .: "input"
            <*> v .:? "user"
            <*> v .:? "encoding_format"
            <*> v .:? "dimensions"

-- | Single embedding data
data EmbeddingData = EmbeddingData
    { edObject :: Text           -- "embedding"
    , edIndex :: Int
    , edEmbedding :: Vector Double
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON EmbeddingData where
    toJSON EmbeddingData{..} = object
        [ "object" .= edObject
        , "index" .= edIndex
        , "embedding" .= edEmbedding
        ]

instance FromJSON EmbeddingData where
    parseJSON = withObject "EmbeddingData" $ \v ->
        EmbeddingData
            <$> v .:? "object" .!= "embedding"
            <*> v .: "index"
            <*> v .: "embedding"

-- | Embedding response
data EmbeddingResponse = EmbeddingResponse
    { embRespObject :: Text      -- "list"
    , embRespData :: [EmbeddingData]
    , embRespModel :: ModelId
    , embRespUsage :: Usage
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON EmbeddingResponse where
    toJSON EmbeddingResponse{..} = object
        [ "object" .= embRespObject
        , "data" .= embRespData
        , "model" .= embRespModel
        , "usage" .= embRespUsage
        ]

instance FromJSON EmbeddingResponse where
    parseJSON = withObject "EmbeddingResponse" $ \v ->
        EmbeddingResponse
            <$> v .:? "object" .!= "list"
            <*> v .: "data"
            <*> v .: "model"
            <*> v .: "usage"


-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // models
-- ════════════════════════════════════════════════════════════════════════════

-- | Model information
data Model = Model
    { modelId :: ModelId
    , modelObject :: Text        -- "model"
    , modelCreated :: Timestamp
    , modelOwnedBy :: Text
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON Model where
    toJSON Model{..} = object
        [ "id" .= modelId
        , "object" .= modelObject
        , "created" .= modelCreated
        , "owned_by" .= modelOwnedBy
        ]

instance FromJSON Model where
    parseJSON = withObject "Model" $ \v ->
        Model
            <$> v .: "id"
            <*> v .:? "object" .!= "model"
            <*> v .:? "created" .!= Timestamp 0
            <*> v .:? "owned_by" .!= "system"

-- | List of models
data ModelList = ModelList
    { mlObject :: Text           -- "list"
    , mlData :: [Model]
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ModelList where
    toJSON ModelList{..} = object
        [ "object" .= mlObject
        , "data" .= mlData
        ]

instance FromJSON ModelList where
    parseJSON = withObject "ModelList" $ \v ->
        ModelList
            <$> v .:? "object" .!= "list"
            <*> v .: "data"


-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // errors
-- ════════════════════════════════════════════════════════════════════════════

-- | Error detail
data ErrorDetail = ErrorDetail
    { errMessage :: Text
    , errType :: Text
    , errParam :: Maybe Text
    , errCode :: Maybe Text
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ErrorDetail where
    toJSON ErrorDetail{..} = object $ filter ((/= Null) . snd)
        [ "message" .= errMessage
        , "type" .= errType
        , "param" .= errParam
        , "code" .= errCode
        ]

instance FromJSON ErrorDetail where
    parseJSON = withObject "ErrorDetail" $ \v ->
        ErrorDetail
            <$> v .: "message"
            <*> v .:? "type" .!= "api_error"
            <*> v .:? "param"
            <*> v .:? "code"

-- | API error response
data ApiError = ApiError
    { apiError :: ErrorDetail
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ApiError where
    toJSON ApiError{..} = object ["error" .= apiError]

instance FromJSON ApiError where
    parseJSON = withObject "ApiError" $ \v ->
        ApiError <$> v .: "error"
