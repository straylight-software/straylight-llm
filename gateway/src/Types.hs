-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                              // straylight-llm // types
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
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Types
    ( -- * Messages
      Message (..)
    , Role (..)
    , ContentPart (..)
    , MessageContent (..)

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
import Data.Text (Text)
import Data.Vector (Vector)
import GHC.Generics (Generic)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // roles
-- ════════════════════════════════════════════════════════════════════════════

data Role = System | User | Assistant | Tool
    deriving (Eq, Show, Generic)

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
--                                                                // messages
-- ════════════════════════════════════════════════════════════════════════════

-- | Content can be text or multimodal (text + images)
data ContentPart
    = TextPart Text
    | ImageUrlPart Text (Maybe Text)  -- url, optional detail level
    deriving (Eq, Show, Generic)

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
    deriving (Eq, Show, Generic)

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
    , msgToolCallId :: Maybe Text         -- For tool result messages
    , msgToolCalls :: Maybe Value         -- Tool calls from assistant
    }
    deriving (Eq, Show, Generic)

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
--                                                        // chat completions
-- ════════════════════════════════════════════════════════════════════════════

-- | Chat completion request (OpenAI format)
data ChatRequest = ChatRequest
    { crModel :: Text
    , crMessages :: [Message]
    , crTemperature :: Maybe Double
    , crTopP :: Maybe Double
    , crN :: Maybe Int
    , crStream :: Maybe Bool
    , crStop :: Maybe Value              -- String or [String]
    , crMaxTokens :: Maybe Int
    , crMaxCompletionTokens :: Maybe Int -- OpenAI's newer field
    , crPresencePenalty :: Maybe Double
    , crFrequencyPenalty :: Maybe Double
    , crLogitBias :: Maybe Value
    , crUser :: Maybe Text
    , crTools :: Maybe Value             -- Tool definitions
    , crToolChoice :: Maybe Value        -- "auto" | "none" | specific tool
    , crResponseFormat :: Maybe Value    -- {"type": "json_object"} etc.
    , crSeed :: Maybe Int
    }
    deriving (Eq, Show, Generic)

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
    deriving (Eq, Show, Generic)

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
    , choiceFinishReason :: Maybe Text
    }
    deriving (Eq, Show, Generic)

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
    { respId :: Text
    , respObject :: Text           -- "chat.completion"
    , respCreated :: Int           -- Unix timestamp
    , respModel :: Text
    , respChoices :: [Choice]
    , respUsage :: Maybe Usage
    , respSystemFingerprint :: Maybe Text
    }
    deriving (Eq, Show, Generic)

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
            <*> v .:? "created" .!= 0
            <*> v .: "model"
            <*> v .: "choices"
            <*> v .:? "usage"
            <*> v .:? "system_fingerprint"


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // streaming
-- ════════════════════════════════════════════════════════════════════════════

-- | Delta in streaming response
data ChoiceDelta = ChoiceDelta
    { deltaIndex :: Int
    , deltaDelta :: Maybe Value      -- Partial message
    , deltaFinishReason :: Maybe Text
    }
    deriving (Eq, Show, Generic)

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
    { chunkId :: Text
    , chunkObject :: Text          -- "chat.completion.chunk"
    , chunkCreated :: Int
    , chunkModel :: Text
    , chunkChoices :: [ChoiceDelta]
    , chunkUsage :: Maybe Usage    -- Only in final chunk with stream_options
    }
    deriving (Eq, Show, Generic)

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
            <*> v .:? "created" .!= 0
            <*> v .: "model"
            <*> v .: "choices"
            <*> v .:? "usage"


-- ════════════════════════════════════════════════════════════════════════════
--                                                   // completions (legacy)
-- ════════════════════════════════════════════════════════════════════════════

-- | Legacy completion request
data CompletionRequest = CompletionRequest
    { complModel :: Text
    , complPrompt :: Text
    , complMaxTokens :: Maybe Int
    , complTemperature :: Maybe Double
    , complTopP :: Maybe Double
    , complN :: Maybe Int
    , complStream :: Maybe Bool
    , complStop :: Maybe Value
    , complPresencePenalty :: Maybe Double
    , complFrequencyPenalty :: Maybe Double
    , complUser :: Maybe Text
    }
    deriving (Eq, Show, Generic)

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
    , ccFinishReason :: Maybe Text
    }
    deriving (Eq, Show, Generic)

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
    { complRespId :: Text
    , complRespObject :: Text
    , complRespCreated :: Int
    , complRespModel :: Text
    , complRespChoices :: [CompletionChoice]
    , complRespUsage :: Maybe Usage
    }
    deriving (Eq, Show, Generic)

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
            <*> v .:? "created" .!= 0
            <*> v .: "model"
            <*> v .: "choices"
            <*> v .:? "usage"


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // embeddings
-- ════════════════════════════════════════════════════════════════════════════

-- | Embedding request
data EmbeddingRequest = EmbeddingRequest
    { embModel :: Text
    , embInput :: Value              -- String or [String]
    , embUser :: Maybe Text
    , embEncodingFormat :: Maybe Text  -- "float" or "base64"
    , embDimensions :: Maybe Int
    }
    deriving (Eq, Show, Generic)

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
    deriving (Eq, Show, Generic)

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
    , embRespModel :: Text
    , embRespUsage :: Usage
    }
    deriving (Eq, Show, Generic)

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
--                                                                  // models
-- ════════════════════════════════════════════════════════════════════════════

-- | Model information
data Model = Model
    { modelId :: Text
    , modelObject :: Text        -- "model"
    , modelCreated :: Int
    , modelOwnedBy :: Text
    }
    deriving (Eq, Show, Generic)

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
            <*> v .:? "created" .!= 0
            <*> v .:? "owned_by" .!= "system"

-- | List of models
data ModelList = ModelList
    { mlObject :: Text           -- "list"
    , mlData :: [Model]
    }
    deriving (Eq, Show, Generic)

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
--                                                                  // errors
-- ════════════════════════════════════════════════════════════════════════════

-- | Error detail
data ErrorDetail = ErrorDetail
    { errMessage :: Text
    , errType :: Text
    , errParam :: Maybe Text
    , errCode :: Maybe Text
    }
    deriving (Eq, Show, Generic)

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
    deriving (Eq, Show, Generic)

instance ToJSON ApiError where
    toJSON ApiError{..} = object ["error" .= apiError]

instance FromJSON ApiError where
    parseJSON = withObject "ApiError" $ \v ->
        ApiError <$> v .: "error"
