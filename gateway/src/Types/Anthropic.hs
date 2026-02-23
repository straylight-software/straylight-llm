{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

-- | Anthropic-native API types
--
-- These types match the Anthropic Messages API format, which is used by
-- weapon-server-hs and other straylight components. They support:
--
--   - Content blocks (text, image, tool_use, tool_result)
--   - Anthropic-style streaming events
--   - Cache token tracking
--
-- For OpenAI-compatible types, see "Types".
--
-- Imported patterns from: weapon-server-hs/src/LLM/Types.hs
module Types.Anthropic
    ( -- * Roles
      Role (..)
    
      -- * Content Blocks
    , ContentBlock (..)
    , ToolUse (..)
    , ToolResult (..)
    , Content (..)
    
      -- * Tool Definitions
    , ToolDefinition (..)
    , ToolInputSchema (..)
    , ToolInput (..)
    
      -- * Messages
    , Message (..)
    
      -- * Request/Response
    , ChatRequest (..)
    , ChatResponse (..)
    , StopReason (..)
    , Usage (..)
    
      -- * Streaming Events (typed)
    , StreamEvent (..)
    , ContentBlockDeltaEvent (..)
    , DeltaType (..)
    , MessageDeltaEvent (..)
    , MessageStartEvent (..)
    ) where

import Data.Aeson
import Data.Text (Text)
import GHC.Generics (Generic)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // roles
-- ════════════════════════════════════════════════════════════════════════════

-- | Message role (Anthropic-style)
data Role = User | Assistant | System
    deriving stock (Eq, Show, Generic)

instance ToJSON Role where
    toJSON User = "user"
    toJSON Assistant = "assistant"
    toJSON System = "system"

instance FromJSON Role where
    parseJSON = withText "Role" $ \case
        "user" -> pure User
        "assistant" -> pure Assistant
        "system" -> pure System
        other -> fail $ "Unknown role: " <> show other


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // content blocks
-- ════════════════════════════════════════════════════════════════════════════

-- | Tool use request from assistant
data ToolUse = ToolUse
    { tuId :: !Text
    , tuName :: !Text
    , tuInput :: !ToolInput  -- Typed tool input
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ToolUse where
    toJSON ToolUse{..} = object
        [ "id" .= tuId
        , "name" .= tuName
        , "input" .= tuInput
        ]

instance FromJSON ToolUse where
    parseJSON = withObject "ToolUse" $ \v ->
        ToolUse
            <$> v .: "id"
            <*> v .: "name"
            <*> v .:? "input" .!= ToolInputEmpty

-- | Tool result from user
data ToolResult = ToolResult
    { trToolUseId :: !Text
    , trContent :: !Text
    , trIsError :: !Bool
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ToolResult where
    toJSON ToolResult{..} = object
        [ "tool_use_id" .= trToolUseId
        , "content" .= trContent
        , "is_error" .= trIsError
        ]

instance FromJSON ToolResult where
    parseJSON = withObject "ToolResult" $ \v ->
        ToolResult
            <$> v .: "tool_use_id"
            <*> v .: "content"
            <*> v .:? "is_error" .!= False

-- | Content block types (Anthropic-native)
data ContentBlock
    = TextBlock !Text
    | ImageBlock !Text !Text  -- media_type, base64 data
    | ToolUseBlock !ToolUse
    | ToolResultBlock !ToolResult
    deriving stock (Eq, Show, Generic)

instance ToJSON ContentBlock where
    toJSON (TextBlock t) = object 
        [ "type" .= ("text" :: Text)
        , "text" .= t
        ]
    toJSON (ImageBlock mediaType b64) = object
        [ "type" .= ("image" :: Text)
        , "source" .= object
            [ "type" .= ("base64" :: Text)
            , "media_type" .= mediaType
            , "data" .= b64
            ]
        ]
    toJSON (ToolUseBlock tu) = object
        [ "type" .= ("tool_use" :: Text)
        , "id" .= tuId tu
        , "name" .= tuName tu
        , "input" .= tuInput tu
        ]
    toJSON (ToolResultBlock tr) = object
        [ "type" .= ("tool_result" :: Text)
        , "tool_use_id" .= trToolUseId tr
        , "content" .= trContent tr
        , "is_error" .= trIsError tr
        ]

instance FromJSON ContentBlock where
    parseJSON = withObject "ContentBlock" $ \v -> do
        typ <- v .: "type"
        case typ :: Text of
            "text" -> TextBlock <$> v .: "text"
            "image" -> do
                source <- v .: "source"
                mediaType <- source .: "media_type"
                b64 <- source .: "data"
                pure $ ImageBlock mediaType b64
            "tool_use" -> ToolUseBlock <$> parseJSON (Object v)
            "tool_result" -> ToolResultBlock <$> parseJSON (Object v)
            other -> fail $ "Unknown content block type: " <> show other

-- | Message content - can be string or blocks
data Content
    = SimpleContent !Text
    | BlockContent ![ContentBlock]
    deriving stock (Eq, Show, Generic)

instance ToJSON Content where
    toJSON (SimpleContent t) = toJSON t
    toJSON (BlockContent bs) = toJSON bs

instance FromJSON Content where
    parseJSON (String t) = pure $ SimpleContent t
    parseJSON (Array a) = BlockContent <$> mapM parseJSON (foldr (:) [] a)
    parseJSON _ = fail "Content must be string or array"


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // tool definitions
-- ════════════════════════════════════════════════════════════════════════════

-- | Tool input - structured JSON object with known schema
-- For truly dynamic inputs, use the Object variant
data ToolInput
    = ToolInputObject !Object    -- ^ Structured input matching tool's input_schema
    | ToolInputEmpty             -- ^ No input required
    deriving stock (Eq, Show, Generic)

instance ToJSON ToolInput where
    toJSON (ToolInputObject obj) = Object obj
    toJSON ToolInputEmpty = object []

instance FromJSON ToolInput where
    parseJSON (Object obj) 
        | null obj  = pure ToolInputEmpty
        | otherwise = pure $ ToolInputObject obj
    parseJSON Null = pure ToolInputEmpty
    parseJSON _ = fail "Tool input must be object or null"

-- | JSON Schema for tool input parameters
-- Uses Aeson Object to preserve schema structure while being typed
data ToolInputSchema = ToolInputSchema
    { tisType :: !Text                     -- ^ Always "object" for Anthropic
    , tisProperties :: !(Maybe Object)     -- ^ Property definitions
    , tisRequired :: !(Maybe [Text])       -- ^ Required property names
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ToolInputSchema where
    toJSON ToolInputSchema{..} = object $ filter ((/= Null) . snd)
        [ "type" .= tisType
        , "properties" .= tisProperties
        , "required" .= tisRequired
        ]

instance FromJSON ToolInputSchema where
    parseJSON = withObject "ToolInputSchema" $ \v ->
        ToolInputSchema
            <$> v .:? "type" .!= "object"
            <*> v .:? "properties"
            <*> v .:? "required"

-- | Tool definition for Anthropic API
data ToolDefinition = ToolDefinition
    { tdName :: !Text                      -- ^ Tool name (identifier)
    , tdDescription :: !(Maybe Text)       -- ^ Human-readable description
    , tdInputSchema :: !ToolInputSchema    -- ^ JSON Schema for input validation
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ToolDefinition where
    toJSON ToolDefinition{..} = object $ filter ((/= Null) . snd)
        [ "name" .= tdName
        , "description" .= tdDescription
        , "input_schema" .= tdInputSchema
        ]

instance FromJSON ToolDefinition where
    parseJSON = withObject "ToolDefinition" $ \v ->
        ToolDefinition
            <$> v .: "name"
            <*> v .:? "description"
            <*> v .: "input_schema"


-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // messages
-- ════════════════════════════════════════════════════════════════════════════

-- | A chat message (Anthropic-style)
data Message = Message
    { msgRole :: !Role
    , msgContent :: !Content
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON Message where
    toJSON Message{..} = object
        [ "role" .= msgRole
        , "content" .= msgContent
        ]

instance FromJSON Message where
    parseJSON = withObject "Message" $ \v ->
        Message
            <$> v .: "role"
            <*> v .: "content"


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // request/response
-- ════════════════════════════════════════════════════════════════════════════

-- | Chat completion request (Anthropic-style)
data ChatRequest = ChatRequest
    { crModel :: !Text
    , crMessages :: ![Message]
    , crMaxTokens :: !Int
    , crSystem :: !(Maybe Text)
    , crTemperature :: !(Maybe Double)
    , crTools :: !(Maybe [ToolDefinition])  -- Typed tool definitions
    , crStream :: !Bool
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ChatRequest where
    toJSON ChatRequest{..} = object $ filter ((/= Null) . snd)
        [ "model" .= crModel
        , "messages" .= crMessages
        , "max_tokens" .= crMaxTokens
        , "system" .= crSystem
        , "temperature" .= crTemperature
        , "tools" .= crTools
        , "stream" .= crStream
        ]

instance FromJSON ChatRequest where
    parseJSON = withObject "ChatRequest" $ \v ->
        ChatRequest
            <$> v .: "model"
            <*> v .: "messages"
            <*> v .: "max_tokens"
            <*> v .:? "system"
            <*> v .:? "temperature"
            <*> v .:? "tools"
            <*> v .:? "stream" .!= False

-- | Stop reason (Anthropic-style ADT)
data StopReason 
    = EndTurn 
    | MaxTokens 
    | ToolUseSR 
    | StopSequence
    deriving stock (Eq, Show, Generic)

instance FromJSON StopReason where
    parseJSON = withText "StopReason" $ \case
        "end_turn" -> pure EndTurn
        "max_tokens" -> pure MaxTokens
        "tool_use" -> pure ToolUseSR
        "stop_sequence" -> pure StopSequence
        _other -> pure EndTurn  -- Default fallback

instance ToJSON StopReason where
    toJSON EndTurn = "end_turn"
    toJSON MaxTokens = "max_tokens"
    toJSON ToolUseSR = "tool_use"
    toJSON StopSequence = "stop_sequence"

-- | Token usage with Anthropic cache fields
data Usage = Usage
    { usageInputTokens :: !Int
    , usageOutputTokens :: !Int
    , usageCacheRead :: !(Maybe Int)   -- cache_read_input_tokens
    , usageCacheWrite :: !(Maybe Int)  -- cache_creation_input_tokens
    }
    deriving stock (Eq, Show, Generic)

instance FromJSON Usage where
    parseJSON = withObject "Usage" $ \v ->
        Usage
            <$> v .: "input_tokens"
            <*> v .: "output_tokens"
            <*> v .:? "cache_read_input_tokens"
            <*> v .:? "cache_creation_input_tokens"

instance ToJSON Usage where
    toJSON Usage{..} = object $ filter ((/= Null) . snd)
        [ "input_tokens" .= usageInputTokens
        , "output_tokens" .= usageOutputTokens
        , "cache_read_input_tokens" .= usageCacheRead
        , "cache_creation_input_tokens" .= usageCacheWrite
        ]

-- | Chat completion response (Anthropic-style)
data ChatResponse = ChatResponse
    { respId :: !Text
    , respModel :: !Text
    , respRole :: !Role
    , respContent :: ![ContentBlock]
    , respStopReason :: !(Maybe StopReason)
    , respUsage :: !Usage
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ChatResponse where
    toJSON ChatResponse{..} = object
        [ "id" .= respId
        , "model" .= respModel
        , "role" .= respRole
        , "content" .= respContent
        , "stop_reason" .= respStopReason
        , "usage" .= respUsage
        ]

instance FromJSON ChatResponse where
    parseJSON = withObject "ChatResponse" $ \v ->
        ChatResponse
            <$> v .: "id"
            <*> v .: "model"
            <*> v .: "role"
            <*> v .: "content"
            <*> v .:? "stop_reason"
            <*> v .: "usage"


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // streaming
-- ════════════════════════════════════════════════════════════════════════════

-- | Delta type in content_block_delta events
data DeltaType
    = TextDelta !Text              -- ^ Text content delta
    | InputJsonDelta !Text         -- ^ Partial JSON for tool input
    deriving stock (Eq, Show, Generic)

instance ToJSON DeltaType where
    toJSON (TextDelta t) = object
        [ "type" .= ("text_delta" :: Text)
        , "text" .= t
        ]
    toJSON (InputJsonDelta j) = object
        [ "type" .= ("input_json_delta" :: Text)
        , "partial_json" .= j
        ]

instance FromJSON DeltaType where
    parseJSON = withObject "DeltaType" $ \v -> do
        typ <- v .: "type"
        case typ :: Text of
            "text_delta" -> TextDelta <$> v .: "text"
            "input_json_delta" -> InputJsonDelta <$> v .: "partial_json"
            other -> fail $ "Unknown delta type: " <> show other

-- | Content block delta event (typed)
data ContentBlockDeltaEvent = ContentBlockDeltaEvent
    { cbdeIndex :: !Int
    , cbdeDelta :: !DeltaType
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON ContentBlockDeltaEvent where
    toJSON ContentBlockDeltaEvent{..} = object
        [ "type" .= ("content_block_delta" :: Text)
        , "index" .= cbdeIndex
        , "delta" .= cbdeDelta
        ]

instance FromJSON ContentBlockDeltaEvent where
    parseJSON = withObject "ContentBlockDeltaEvent" $ \v -> do
        typ <- v .: "type"
        case typ :: Text of
            "content_block_delta" ->
                ContentBlockDeltaEvent
                    <$> v .: "index"
                    <*> v .: "delta"
            other -> fail $ "Expected content_block_delta, got: " <> show other

-- | Message delta event (stop reason and final usage)
data MessageDeltaEvent = MessageDeltaEvent
    { mdeStopReason :: !(Maybe StopReason)
    , mdeUsage :: !(Maybe Usage)
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON MessageDeltaEvent where
    toJSON MessageDeltaEvent{..} = object
        [ "type" .= ("message_delta" :: Text)
        , "delta" .= object (filter ((/= Null) . snd)
            [ "stop_reason" .= mdeStopReason
            ])
        , "usage" .= mdeUsage
        ]

instance FromJSON MessageDeltaEvent where
    parseJSON = withObject "MessageDeltaEvent" $ \v -> do
        typ <- v .: "type"
        case typ :: Text of
            "message_delta" -> do
                delta <- v .: "delta"
                MessageDeltaEvent
                    <$> delta .:? "stop_reason"
                    <*> v .:? "usage"
            other -> fail $ "Expected message_delta, got: " <> show other

-- | Message start event (initial message structure)
data MessageStartEvent = MessageStartEvent
    { mseMessage :: !ChatResponse
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON MessageStartEvent where
    toJSON MessageStartEvent{..} = object
        [ "type" .= ("message_start" :: Text)
        , "message" .= mseMessage
        ]

instance FromJSON MessageStartEvent where
    parseJSON = withObject "MessageStartEvent" $ \v -> do
        typ <- v .: "type"
        case typ :: Text of
            "message_start" ->
                MessageStartEvent <$> v .: "message"
            other -> fail $ "Expected message_start, got: " <> show other

-- | Streaming event types (Anthropic-style)
-- Now fully parseable with proper JSON instances
data StreamEvent
    = EventMessageStart !MessageStartEvent
    | EventContentBlockStart !Int !ContentBlock  -- index, block
    | EventContentBlockDelta !ContentBlockDeltaEvent
    | EventContentBlockStop !Int                 -- index
    | EventMessageDelta !MessageDeltaEvent
    | EventMessageStop
    | EventPing
    | EventError !Text                           -- error message
    deriving stock (Eq, Show, Generic)

instance ToJSON StreamEvent where
    toJSON (EventMessageStart e) = toJSON e
    toJSON (EventContentBlockStart idx block) = object
        [ "type" .= ("content_block_start" :: Text)
        , "index" .= idx
        , "content_block" .= block
        ]
    toJSON (EventContentBlockDelta e) = toJSON e
    toJSON (EventContentBlockStop idx) = object
        [ "type" .= ("content_block_stop" :: Text)
        , "index" .= idx
        ]
    toJSON (EventMessageDelta e) = toJSON e
    toJSON EventMessageStop = object
        [ "type" .= ("message_stop" :: Text)
        ]
    toJSON EventPing = object
        [ "type" .= ("ping" :: Text)
        ]
    toJSON (EventError msg) = object
        [ "type" .= ("error" :: Text)
        , "error" .= object [ "message" .= msg ]
        ]

instance FromJSON StreamEvent where
    parseJSON = withObject "StreamEvent" $ \v -> do
        typ <- v .: "type"
        case typ :: Text of
            "message_start" -> EventMessageStart <$> parseJSON (Object v)
            "content_block_start" -> EventContentBlockStart
                <$> v .: "index"
                <*> v .: "content_block"
            "content_block_delta" -> EventContentBlockDelta <$> parseJSON (Object v)
            "content_block_stop" -> EventContentBlockStop <$> v .: "index"
            "message_delta" -> EventMessageDelta <$> parseJSON (Object v)
            "message_stop" -> pure EventMessageStop
            "ping" -> pure EventPing
            "error" -> do
                err <- v .: "error"
                EventError <$> err .: "message"
            other -> fail $ "Unknown stream event type: " <> show other
