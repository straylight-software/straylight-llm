{-# LANGUAGE LambdaCase #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                        // straylight // types
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   "The matrix has its roots in primitive arcade games... in
    early graphics programs and military experimentation with
    cranial jacks."

                                                               — Neuromancer

   Core OpenAI-compatible type definitions.
   n.b. corresponds to Lean4 Straylight.Types with runtime encoding.
-}
module Straylight.Types
  ( -- // chat // messages
    Role (..)
  , Content (..)
  , ContentPart (..)
  , ImageUrl (..)
  , FunctionCall (..)
  , ToolCall (..)
  , ChatMessage (..)
    -- // tools // definitions
  , FunctionDef (..)
  , Tool (..)
  , ToolChoice (..)
    -- // response // types
  , ResponseFormat (..)
  , Usage (..)
  , FinishReason (..)
    -- // chat // response
  , ChatChoice (..)
  , ChatResponse (..)
  , ChatDelta (..)
  , StreamChoice (..)
  , StreamChunk (..)
    -- // models // endpoint
  , ModelInfo (..)
  , ModelsResponse (..)
    -- // error // response
  , ErrorDetail (..)
  , ErrorResponse (..)
    -- // health // response
  , HealthStatus (..)
  , BackendHealth (..)
  , HealthResponse (..)
  ) where

import Data.Aeson
import Data.Aeson.Types (Parser)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import GHC.Generics (Generic)


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // chat // messages
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Role in a chat conversation.
--   cf. OpenAI Chat Completions API specification
data Role
  = RoleAssistant
  | RoleSystem
  | RoleTool
  | RoleUser
  deriving stock (Eq, Show, Generic)

instance FromJSON Role where
  parseJSON = withText "Role" $ \case
    "assistant" -> pure RoleAssistant
    "system"    -> pure RoleSystem
    "tool"      -> pure RoleTool
    "user"      -> pure RoleUser
    other       -> fail $ "Unknown role: " <> show other

instance ToJSON Role where
  toJSON = \case
    RoleAssistant -> String "assistant"
    RoleSystem    -> String "system"
    RoleTool      -> String "tool"
    RoleUser      -> String "user"


{- ────────────────────────────────────────────────────────────────────────────────
                                                        // content // variants
   ──────────────────────────────────────────────────────────────────────────────── -}

-- | Image URL with optional detail level.
--   i.e. for vision models
data ImageUrl = ImageUrl
  { imageUrl    :: !Text
  , imageDetail :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON ImageUrl where
  parseJSON = withObject "ImageUrl" $ \v -> ImageUrl
    <$> v .:  "url"
    <*> v .:? "detail"

instance ToJSON ImageUrl where
  toJSON ImageUrl{..} = object $ catMaybes
    [ Just $ "url"    .= imageUrl
    , ("detail" .=) <$> imageDetail
    ]

-- | A part of multimodal content
data ContentPart
  = ContentPartImage !ImageUrl
  | ContentPartText  !Text
  deriving stock (Eq, Show, Generic)

instance FromJSON ContentPart where
  parseJSON = withObject "ContentPart" $ \v -> do
    partType <- v .: "type" :: Parser Text
    case partType of
      "text"      -> ContentPartText <$> v .: "text"
      "image_url" -> ContentPartImage <$> v .: "image_url"
      other       -> fail $ "Unknown content part type: " <> show other

instance ToJSON ContentPart where
  toJSON = \case
    ContentPartText t -> object
      [ "type" .= ("text" :: Text)
      , "text" .= t
      ]
    ContentPartImage i -> object
      [ "type"      .= ("image_url" :: Text)
      , "image_url" .= i
      ]

-- | Content can be text or structured (for multimodal)
data Content
  = ContentParts ![ContentPart]
  | ContentText  !Text
  deriving stock (Eq, Show, Generic)

instance FromJSON Content where
  parseJSON v = case v of
    String t -> pure $ ContentText t
    Array _  -> ContentParts <$> parseJSON v
    _        -> fail "Content must be string or array"

instance ToJSON Content where
  toJSON = \case
    ContentText t  -> String t
    ContentParts p -> toJSON p


{- ────────────────────────────────────────────────────────────────────────────────
                                                        // tool // calls
   ──────────────────────────────────────────────────────────────────────────────── -}

-- | Function call details
data FunctionCall = FunctionCall
  { fnName      :: !Text
  , fnArguments :: !Text  -- n.b. JSON string
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON FunctionCall where
  parseJSON = withObject "FunctionCall" $ \v -> FunctionCall
    <$> v .: "name"
    <*> v .: "arguments"

instance ToJSON FunctionCall where
  toJSON FunctionCall{..} = object
    [ "name"      .= fnName
    , "arguments" .= fnArguments
    ]

-- | Tool call in assistant messages
data ToolCall = ToolCall
  { tcId       :: !Text
  , tcType     :: !Text  -- n.b. always "function" for now
  , tcFunction :: !FunctionCall
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON ToolCall where
  parseJSON = withObject "ToolCall" $ \v -> ToolCall
    <$> v .: "id"
    <*> v .: "type"
    <*> v .: "function"

instance ToJSON ToolCall where
  toJSON ToolCall{..} = object
    [ "id"       .= tcId
    , "type"     .= tcType
    , "function" .= tcFunction
    ]


{- ────────────────────────────────────────────────────────────────────────────────
                                                        // chat // message
   ──────────────────────────────────────────────────────────────────────────────── -}

-- | A single chat message
data ChatMessage = ChatMessage
  { msgRole       :: !Role
  , msgContent    :: !(Maybe Content)
  , msgName       :: !(Maybe Text)
  , msgToolCallId :: !(Maybe Text)
  , msgToolCalls  :: !(Maybe [ToolCall])
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON ChatMessage where
  parseJSON = withObject "ChatMessage" $ \v -> ChatMessage
    <$> v .:  "role"
    <*> v .:? "content"
    <*> v .:? "name"
    <*> v .:? "tool_call_id"
    <*> v .:? "tool_calls"

instance ToJSON ChatMessage where
  toJSON ChatMessage{..} = object $ catMaybes
    [ Just $ "role" .= msgRole
    , ("content" .=)      <$> msgContent
    , ("name" .=)         <$> msgName
    , ("tool_call_id" .=) <$> msgToolCallId
    , ("tool_calls" .=)   <$> msgToolCalls
    ]


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // tools // definitions
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Tool function definition
data FunctionDef = FunctionDef
  { fdName        :: !Text
  , fdDescription :: !(Maybe Text)
  , fdParameters  :: !(Maybe Value)  -- n.b. JSON Schema
  , fdStrict      :: !(Maybe Bool)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON FunctionDef where
  parseJSON = withObject "FunctionDef" $ \v -> FunctionDef
    <$> v .:  "name"
    <*> v .:? "description"
    <*> v .:? "parameters"
    <*> v .:? "strict"

instance ToJSON FunctionDef where
  toJSON FunctionDef{..} = object $ catMaybes
    [ Just $ "name" .= fdName
    , ("description" .=) <$> fdDescription
    , ("parameters" .=)  <$> fdParameters
    , ("strict" .=)      <$> fdStrict
    ]

-- | Tool definition wrapper
data Tool = Tool
  { toolType     :: !Text  -- n.b. always "function"
  , toolFunction :: !FunctionDef
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON Tool where
  parseJSON = withObject "Tool" $ \v -> Tool
    <$> v .: "type"
    <*> v .: "function"

instance ToJSON Tool where
  toJSON Tool{..} = object
    [ "type"     .= toolType
    , "function" .= toolFunction
    ]

-- | Tool choice specification
data ToolChoice
  = ToolChoiceAuto
  | ToolChoiceNone
  | ToolChoiceRequired
  | ToolChoiceSpecific !Text  -- function name
  deriving stock (Eq, Show, Generic)

instance FromJSON ToolChoice where
  parseJSON v = case v of
    String "auto"     -> pure ToolChoiceAuto
    String "none"     -> pure ToolChoiceNone
    String "required" -> pure ToolChoiceRequired
    Object o          -> ToolChoiceSpecific <$> (o .: "function" >>= (.: "name"))
    _                 -> fail "Invalid tool_choice"

instance ToJSON ToolChoice where
  toJSON = \case
    ToolChoiceAuto     -> String "auto"
    ToolChoiceNone     -> String "none"
    ToolChoiceRequired -> String "required"
    ToolChoiceSpecific n -> object
      [ "type" .= ("function" :: Text)
      , "function" .= object ["name" .= n]
      ]


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // response // format
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Response format specification.
--   cf. OpenAI structured outputs
data ResponseFormat
  = ResponseFormatJson
  | ResponseFormatJsonSchema !Value
  | ResponseFormatText
  deriving stock (Eq, Show, Generic)

instance FromJSON ResponseFormat where
  parseJSON = withObject "ResponseFormat" $ \v -> do
    formatType <- v .: "type" :: Parser Text
    case formatType of
      "text"        -> pure ResponseFormatText
      "json_object" -> pure ResponseFormatJson
      "json_schema" -> ResponseFormatJsonSchema <$> v .: "json_schema"
      other         -> fail $ "Unknown response_format type: " <> show other

instance ToJSON ResponseFormat where
  toJSON = \case
    ResponseFormatText -> object ["type" .= ("text" :: Text)]
    ResponseFormatJson -> object ["type" .= ("json_object" :: Text)]
    ResponseFormatJsonSchema s -> object
      [ "type"        .= ("json_schema" :: Text)
      , "json_schema" .= s
      ]


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // usage // statistics
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Token usage statistics
data Usage = Usage
  { usagePromptTokens     :: !Int
  , usageCompletionTokens :: !Int
  , usageTotalTokens      :: !Int
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON Usage where
  parseJSON = withObject "Usage" $ \v -> Usage
    <$> v .: "prompt_tokens"
    <*> v .: "completion_tokens"
    <*> v .: "total_tokens"

instance ToJSON Usage where
  toJSON Usage{..} = object
    [ "prompt_tokens"     .= usagePromptTokens
    , "completion_tokens" .= usageCompletionTokens
    , "total_tokens"      .= usageTotalTokens
    ]


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // finish // reasons
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Why the model stopped generating
data FinishReason
  = FinishContentFilter
  | FinishFunctionCall  -- n.b. deprecated
  | FinishLength
  | FinishStop
  | FinishToolCalls
  deriving stock (Eq, Show, Generic)

instance FromJSON FinishReason where
  parseJSON = withText "FinishReason" $ \case
    "content_filter" -> pure FinishContentFilter
    "function_call"  -> pure FinishFunctionCall
    "length"         -> pure FinishLength
    "stop"           -> pure FinishStop
    "tool_calls"     -> pure FinishToolCalls
    other            -> fail $ "Unknown finish_reason: " <> show other

instance ToJSON FinishReason where
  toJSON = \case
    FinishContentFilter -> String "content_filter"
    FinishFunctionCall  -> String "function_call"
    FinishLength        -> String "length"
    FinishStop          -> String "stop"
    FinishToolCalls     -> String "tool_calls"


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // chat // response
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | A single choice in a chat completion response
data ChatChoice = ChatChoice
  { choiceIndex        :: !Int
  , choiceMessage      :: !ChatMessage
  , choiceFinishReason :: !(Maybe FinishReason)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON ChatChoice where
  parseJSON = withObject "ChatChoice" $ \v -> ChatChoice
    <$> v .:  "index"
    <*> v .:  "message"
    <*> v .:? "finish_reason"

instance ToJSON ChatChoice where
  toJSON ChatChoice{..} = object $ catMaybes
    [ Just $ "index"   .= choiceIndex
    , Just $ "message" .= choiceMessage
    , ("finish_reason" .=) <$> choiceFinishReason
    ]

-- | Chat completion response.
--   cf. OpenAI POST /v1/chat/completions response
data ChatResponse = ChatResponse
  { respId      :: !Text
  , respObject  :: !Text  -- n.b. always "chat.completion"
  , respCreated :: !Int   -- Unix timestamp
  , respModel   :: !Text
  , respChoices :: ![ChatChoice]
  , respUsage   :: !(Maybe Usage)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON ChatResponse where
  parseJSON = withObject "ChatResponse" $ \v -> ChatResponse
    <$> v .:  "id"
    <*> v .:? "object" .!= "chat.completion"
    <*> v .:  "created"
    <*> v .:  "model"
    <*> v .:  "choices"
    <*> v .:? "usage"

instance ToJSON ChatResponse where
  toJSON ChatResponse{..} = object $ catMaybes
    [ Just $ "id"      .= respId
    , Just $ "object"  .= respObject
    , Just $ "created" .= respCreated
    , Just $ "model"   .= respModel
    , Just $ "choices" .= respChoices
    , ("usage" .=) <$> respUsage
    ]


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // streaming // types
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Delta in a streaming response.
--   n.b. partial updates sent via SSE
data ChatDelta = ChatDelta
  { deltaContent :: !(Maybe Text)
  , deltaRole    :: !(Maybe Role)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON ChatDelta where
  parseJSON = withObject "ChatDelta" $ \v -> ChatDelta
    <$> v .:? "content"
    <*> v .:? "role"

instance ToJSON ChatDelta where
  toJSON ChatDelta{..} = object $ catMaybes
    [ ("content" .=) <$> deltaContent
    , ("role" .=)    <$> deltaRole
    ]

-- | A choice in a streaming chunk
data StreamChoice = StreamChoice
  { scIndex        :: !Int
  , scDelta        :: !ChatDelta
  , scFinishReason :: !(Maybe FinishReason)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON StreamChoice where
  parseJSON = withObject "StreamChoice" $ \v -> StreamChoice
    <$> v .:  "index"
    <*> v .:  "delta"
    <*> v .:? "finish_reason"

instance ToJSON StreamChoice where
  toJSON StreamChoice{..} = object $ catMaybes
    [ Just $ "index" .= scIndex
    , Just $ "delta" .= scDelta
    , ("finish_reason" .=) <$> scFinishReason
    ]

-- | Streaming chunk.
--   cf. SSE data: {...} format
data StreamChunk = StreamChunk
  { scId      :: !Text
  , scObject  :: !Text  -- n.b. always "chat.completion.chunk"
  , scCreated :: !Int
  , scModel   :: !Text
  , scChoices :: ![StreamChoice]
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON StreamChunk where
  parseJSON = withObject "StreamChunk" $ \v -> StreamChunk
    <$> v .:  "id"
    <*> v .:? "object" .!= "chat.completion.chunk"
    <*> v .:  "created"
    <*> v .:  "model"
    <*> v .:  "choices"

instance ToJSON StreamChunk where
  toJSON StreamChunk{..} = object
    [ "id"      .= scId
    , "object"  .= scObject
    , "created" .= scCreated
    , "model"   .= scModel
    , "choices" .= scChoices
    ]


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // models // endpoint
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Model information from /v1/models endpoint
data ModelInfo = ModelInfo
  { modelId      :: !Text
  , modelObject  :: !Text  -- n.b. always "model"
  , modelCreated :: !Int   -- Unix timestamp
  , modelOwnedBy :: !Text
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON ModelInfo where
  toJSON ModelInfo{..} = object
    [ "id"       .= modelId
    , "object"   .= modelObject
    , "created"  .= modelCreated
    , "owned_by" .= modelOwnedBy
    ]

-- | Models list response
data ModelsResponse = ModelsResponse
  { modelsObject :: !Text  -- n.b. always "list"
  , modelsData   :: ![ModelInfo]
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON ModelsResponse where
  toJSON ModelsResponse{..} = object
    [ "object" .= modelsObject
    , "data"   .= modelsData
    ]


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // error // response
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Error detail
data ErrorDetail = ErrorDetail
  { errMessage :: !Text
  , errType    :: !Text
  , errCode    :: !(Maybe Text)
  , errParam   :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON ErrorDetail where
  toJSON ErrorDetail{..} = object $ catMaybes
    [ Just $ "message" .= errMessage
    , Just $ "type"    .= errType
    , ("code" .=)  <$> errCode
    , ("param" .=) <$> errParam
    ]

-- | Error response.
--   cf. OpenAI error format
data ErrorResponse = ErrorResponse
  { errError :: !ErrorDetail
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON ErrorResponse where
  toJSON ErrorResponse{..} = object
    [ "error" .= errError
    ]


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // health // response
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Health status enumeration
data HealthStatus
  = HealthDegraded
  | HealthOk
  | HealthUnhealthy
  deriving stock (Eq, Show, Generic)

instance ToJSON HealthStatus where
  toJSON = \case
    HealthDegraded  -> String "degraded"
    HealthOk        -> String "ok"
    HealthUnhealthy -> String "unhealthy"

-- | Backend health info
data BackendHealth = BackendHealth
  { bhConfigured :: !Bool
  , bhHealthy    :: !Bool
  , bhApiBase    :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON BackendHealth where
  toJSON BackendHealth{..} = object $ catMaybes
    [ Just $ "configured" .= bhConfigured
    , Just $ "healthy"    .= bhHealthy
    , ("api_base" .=) <$> bhApiBase
    ]

-- | Health check response.
--   n.b. straylight-llm specific endpoint
data HealthResponse = HealthResponse
  { hrStatus     :: !HealthStatus
  , hrCgp        :: !BackendHealth
  , hrOpenRouter :: !BackendHealth
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON HealthResponse where
  toJSON HealthResponse{..} = object
    [ "status"     .= hrStatus
    , "cgp"        .= hrCgp
    , "openrouter" .= hrOpenRouter
    ]
