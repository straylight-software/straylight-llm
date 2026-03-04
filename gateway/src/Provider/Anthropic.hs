-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // straylight-llm // provider/anthropic
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Straylight was a parasitic structure, most of it run to dream castles,
--      halls of mirrors, chambers floored with clouds."
--
--                                                              — Neuromancer
--
-- Anthropic provider backend. Native Messages API implementation with:
--   - Content blocks (text, image, tool_use, tool_result)
--   - Anthropic-style streaming events
--   - Cache token tracking
--   - Tool use with coeffect tracking
--
-- Uses Types.Anthropic for Anthropic-native types, not OpenAI-compatible.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.Anthropic
  ( -- * Provider
    makeAnthropicProvider,

    -- * Direct API (for native Anthropic access)
    anthropicChat,
    anthropicChatStream,
  )
where

import Config (ProviderConfig (pcApiKey, pcBaseUrl, pcEnabled))
import Control.Exception (try)
import Data.Aeson (eitherDecode, encode)
import Data.Aeson qualified as Aeson
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Effects.Do qualified as G
import Effects.Graded
  ( Full,
    GatewayM,
    liftIO',
    recordAuthUsage,
    recordConfigAccess,
    recordHttpAccess,
    recordModel,
    recordProvider,
    withLatency,
  )
import Network.HTTP.Client (HttpException)
import Network.HTTP.Client qualified as HC
import Network.HTTP.Types qualified as HT
import Provider.Types
  ( Provider (..),
    ProviderError (..),
    ProviderName (Anthropic),
    ProviderResult (..),
    RequestContext (..),
    StreamCallback,
  )
import Types qualified as OpenAI
import Types.Anthropic qualified as A

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | Create an Anthropic provider
--
-- This provider uses the native Anthropic Messages API, but wraps it in the
-- OpenAI-compatible interface required by Provider.Types. For direct access
-- to Anthropic-native types, use 'anthropicChat' and 'anthropicChatStream'.
makeAnthropicProvider :: IORef ProviderConfig -> Provider
makeAnthropicProvider configRef =
  Provider
    { providerName = Anthropic,
      providerEnabled = isEnabled configRef,
      providerChat = chat configRef,
      providerChatStream = chatStream configRef,
      providerEmbeddings = embeddings,
      providerModels = models configRef,
      providerSupportsModel = supportsModel
    }

-- | Check if Anthropic is configured
isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "anthropic.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing

-- | Check if model is supported (Claude models)
supportsModel :: Text -> Bool
supportsModel modelId =
  any
    (`T.isPrefixOf` modelId)
    [ "claude-",
      "anthropic/" -- OpenRouter-style prefix
    ]

-- | Non-streaming chat completion (OpenAI-compatible wrapper)
chat :: IORef ProviderConfig -> RequestContext -> OpenAI.ChatRequest -> GatewayM Full (ProviderResult OpenAI.ChatResponse)
chat configRef ctx req = G.do
  recordProvider "anthropic"
  recordModel (OpenAI.unModelId $ OpenAI.crModel req)
  config <- liftIO' $ readIORef configRef
  chatWithConfig config ctx req

-- | Chat helper after config loaded
chatWithConfig :: ProviderConfig -> RequestContext -> OpenAI.ChatRequest -> GatewayM Full (ProviderResult OpenAI.ChatResponse)
chatWithConfig config ctx req =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Anthropic API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "anthropic" "api-key"
      -- Convert OpenAI request to Anthropic format
      let anthropicReq = toAnthropicRequest req
          url = T.unpack (pcBaseUrl config) <> "/messages"
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- withLatency $ makeRequest (rcManager ctx) url apiKey (encode anthropicReq)
      liftIO' $ pure $ case result of
        Left err -> classifyError err
        Right body -> case eitherDecode body of
          Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
          Right resp -> Success $ fromAnthropicResponse resp

-- | Streaming chat completion (OpenAI-compatible wrapper)
chatStream :: IORef ProviderConfig -> RequestContext -> OpenAI.ChatRequest -> StreamCallback -> GatewayM Full (ProviderResult ())
chatStream configRef ctx req callback = G.do
  recordProvider "anthropic"
  recordModel (OpenAI.unModelId $ OpenAI.crModel req)
  config <- liftIO' $ readIORef configRef
  chatStreamWithConfig config ctx req callback

-- | Streaming chat helper after config loaded
chatStreamWithConfig :: ProviderConfig -> RequestContext -> OpenAI.ChatRequest -> StreamCallback -> GatewayM Full (ProviderResult ())
chatStreamWithConfig config ctx req callback =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Anthropic API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "anthropic" "api-key"
      let anthropicReq = (toAnthropicRequest req) {A.crStream = True}
          url = T.unpack (pcBaseUrl config) <> "/messages"
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- withLatency $ makeStreamingRequest (rcManager ctx) url apiKey (encode anthropicReq) callback
      liftIO' $ pure $ case result of
        Left err -> classifyError err
        Right () -> Success ()

-- | Anthropic doesn't provide embeddings
embeddings :: RequestContext -> OpenAI.EmbeddingRequest -> GatewayM Full (ProviderResult OpenAI.EmbeddingResponse)
embeddings _ctx _req = G.do
  recordProvider "anthropic"
  liftIO' $ pure $ Failure $ ModelNotFoundError "Anthropic does not provide embedding models"

-- | List available models
models :: IORef ProviderConfig -> RequestContext -> GatewayM Full (ProviderResult OpenAI.ModelList)
models configRef ctx = G.do
  recordProvider "anthropic"
  config <- liftIO' $ readIORef configRef
  modelsWithConfig config ctx

-- | Models helper after config loaded
modelsWithConfig :: ProviderConfig -> RequestContext -> GatewayM Full (ProviderResult OpenAI.ModelList)
modelsWithConfig config ctx =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Anthropic API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "anthropic" "api-key"
      let url = T.unpack (pcBaseUrl config) <> "/models"
      recordHttpAccess (T.pack url) "GET" Nothing
      result <- withLatency $ makeModelsRequest (rcManager ctx) url apiKey
      liftIO' $ pure $ case result of
        Left err -> classifyError err
        Right body -> case eitherDecode body of
          Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
          Right anthropicModels -> Success $ toOpenAIModelList anthropicModels

-- | Anthropic model response type
data AnthropicModel = AnthropicModel
  { amId :: Text,
    amDisplayName :: Text,
    amCreatedAt :: Text
  }
  deriving (Show)

instance Aeson.FromJSON AnthropicModel where
  parseJSON = Aeson.withObject "AnthropicModel" $ \v ->
    AnthropicModel
      <$> v Aeson..: "id"
      <*> v Aeson..: "display_name"
      <*> v Aeson..: "created_at"

data AnthropicModelList = AnthropicModelList
  { amlData :: [AnthropicModel]
  }
  deriving (Show)

instance Aeson.FromJSON AnthropicModelList where
  parseJSON = Aeson.withObject "AnthropicModelList" $ \v ->
    AnthropicModelList <$> v Aeson..: "data"

-- | Convert Anthropic model list to OpenAI format
toOpenAIModelList :: AnthropicModelList -> OpenAI.ModelList
toOpenAIModelList AnthropicModelList {..} =
  OpenAI.ModelList
    { OpenAI.mlObject = "list",
      OpenAI.mlData = map toOpenAIModel amlData
    }
  where
    toOpenAIModel AnthropicModel {..} =
      OpenAI.Model
        { OpenAI.modelId = OpenAI.ModelId amId,
          OpenAI.modelObject = "model",
          OpenAI.modelCreated = OpenAI.Timestamp 0, -- Could parse amCreatedAt
          OpenAI.modelOwnedBy = "Anthropic"
        }

-- | Make GET request to Anthropic models endpoint
makeModelsRequest :: HC.Manager -> String -> Text -> IO (Either (Int, Text) LBS.ByteString)
makeModelsRequest manager url apiKey = do
  initReq <- HC.parseRequest url
  let req =
        initReq
          { HC.method = "GET",
            HC.requestHeaders =
              [ ("x-api-key", encodeUtf8 apiKey),
                ("anthropic-version", "2023-06-01")
              ]
          }

  result <- try @HttpException $ HC.httpLbs req manager
  case result of
    Left e -> pure $ Left (0, T.pack $ show e)
    Right resp -> do
      let status = HT.statusCode $ HC.responseStatus resp
      if status >= 200 && status < 300
        then pure $ Right $ HC.responseBody resp
        else pure $ Left (status, decodeUtf8 $ LBS.toStrict $ HC.responseBody resp)

-- ════════════════════════════════════════════════════════════════════════════
--                                                       // direct anthropic api
-- ════════════════════════════════════════════════════════════════════════════

-- | Direct Anthropic chat (native types)
anthropicChat ::
  HC.Manager ->
  -- | API key
  Text ->
  -- | Base URL
  Text ->
  A.ChatRequest ->
  GatewayM Full (ProviderResult A.ChatResponse)
anthropicChat manager apiKey baseUrl req = G.do
  recordProvider "anthropic"
  recordModel (A.crModel req)
  recordAuthUsage "anthropic" "api-key"
  let url = T.unpack baseUrl <> "/messages"
  recordHttpAccess (T.pack url) "POST" Nothing
  result <- withLatency $ makeRequest manager url apiKey (encode req)
  liftIO' $ pure $ case result of
    Left err -> classifyError err
    Right body -> case eitherDecode body of
      Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
      Right resp -> Success resp

-- | Direct Anthropic streaming chat (native types)
--
-- Calls the handler for each content delta. Accumulates tool calls and returns
-- them along with the final usage stats.
anthropicChatStream ::
  HC.Manager ->
  -- | API key
  Text ->
  -- | Base URL
  Text ->
  A.ChatRequest ->
  -- | Content delta handler
  (Text -> IO ()) ->
  GatewayM Full (ProviderResult StreamResult)
anthropicChatStream manager apiKey baseUrl req onDelta = G.do
  recordProvider "anthropic"
  recordModel (A.crModel req)
  recordAuthUsage "anthropic" "api-key"
  let streamReq = req {A.crStream = True}
      url = T.unpack baseUrl <> "/messages"
  recordHttpAccess (T.pack url) "POST" Nothing

  -- Track state across stream
  toolCallsRef <- liftIO' $ newIORef ([] :: [A.ToolUse])
  stopReasonRef <- liftIO' $ newIORef (Nothing :: Maybe A.StopReason)
  usageRef <- liftIO' $ newIORef (Nothing :: Maybe A.Usage)

  result <-
    withLatency $
      makeStreamingRequestWithParsing
        manager
        url
        apiKey
        (encode streamReq)
        onDelta
        toolCallsRef
        stopReasonRef
        usageRef

  anthropicChatStreamResult result toolCallsRef stopReasonRef usageRef

-- | Process stream result
anthropicChatStreamResult ::
  Either (Int, Text) () ->
  IORef [A.ToolUse] ->
  IORef (Maybe A.StopReason) ->
  IORef (Maybe A.Usage) ->
  GatewayM Full (ProviderResult StreamResult)
anthropicChatStreamResult result toolCallsRef stopReasonRef usageRef =
  case result of
    Left err -> liftIO' $ pure $ classifyError err
    Right () -> G.do
      toolCalls <- liftIO' $ readIORef toolCallsRef
      stopReason <- liftIO' $ readIORef stopReasonRef
      usage <- liftIO' $ readIORef usageRef
      liftIO' $
        pure $
          Success $
            StreamResult
              { srStopReason = stopReason,
                srToolCalls = toolCalls,
                srUsage = usage
              }

-- | Result from streaming with tool calls
data StreamResult = StreamResult
  { srStopReason :: Maybe A.StopReason,
    srToolCalls :: [A.ToolUse],
    srUsage :: Maybe A.Usage
  }
  deriving (Eq, Show)

-- ════════════════════════════════════════════════════════════════════════════
--                                                              // conversion
-- ════════════════════════════════════════════════════════════════════════════

-- | Convert OpenAI ChatRequest to Anthropic format
toAnthropicRequest :: OpenAI.ChatRequest -> A.ChatRequest
toAnthropicRequest OpenAI.ChatRequest {..} =
  A.ChatRequest
    { A.crModel = OpenAI.unModelId crModel,
      A.crMessages = convertMessages crMessages,
      A.crMaxTokens = maybe 4096 OpenAI.unMaxTokens crMaxTokens, -- Anthropic requires max_tokens
      A.crSystem = extractSystemMessage crMessages,
      A.crTemperature = fmap OpenAI.unTemperature crTemperature,
      A.crTools = Nothing, -- Would need tool conversion
      A.crStream = crStream == Just True
    }

-- | Extract system message from OpenAI messages
extractSystemMessage :: [OpenAI.Message] -> Maybe Text
extractSystemMessage msgs =
  case [c | OpenAI.Message OpenAI.System (Just c) _ _ _ <- msgs] of
    [] -> Nothing
    (m : _) -> Just $ extractContent m

-- | Convert OpenAI messages to Anthropic format (excluding system)
convertMessages :: [OpenAI.Message] -> [A.Message]
convertMessages = map toAnthropicMessage . filter (not . isSystem)
  where
    isSystem (OpenAI.Message OpenAI.System _ _ _ _) = True
    isSystem _ = False

-- | Convert single OpenAI message to Anthropic
toAnthropicMessage :: OpenAI.Message -> A.Message
toAnthropicMessage OpenAI.Message {..} =
  A.Message
    { A.msgRole = toAnthropicRole msgRole,
      A.msgContent = A.SimpleContent $ maybe "" extractContent msgContent
    }

-- | Convert role
toAnthropicRole :: OpenAI.Role -> A.Role
toAnthropicRole OpenAI.User = A.User
toAnthropicRole OpenAI.Assistant = A.Assistant
toAnthropicRole OpenAI.System = A.System
toAnthropicRole OpenAI.Tool = A.User -- Map tool to user for Anthropic

-- | Extract text content from OpenAI content type
extractContent :: OpenAI.MessageContent -> Text
extractContent (OpenAI.TextContent t) = t
extractContent (OpenAI.PartsContent parts) =
  T.concat [t | OpenAI.TextPart t <- parts]

-- | Convert Anthropic response to OpenAI format
fromAnthropicResponse :: A.ChatResponse -> OpenAI.ChatResponse
fromAnthropicResponse A.ChatResponse {..} =
  OpenAI.ChatResponse
    { OpenAI.respId = OpenAI.ResponseId respId,
      OpenAI.respObject = "chat.completion",
      OpenAI.respCreated = OpenAI.Timestamp 0, -- Anthropic doesn't provide timestamp
      OpenAI.respModel = OpenAI.ModelId respModel,
      OpenAI.respChoices = [choice],
      OpenAI.respUsage = Just $ fromAnthropicUsage respUsage,
      OpenAI.respSystemFingerprint = Nothing
    }
  where
    choice =
      OpenAI.Choice
        { OpenAI.choiceIndex = 0,
          OpenAI.choiceMessage =
            OpenAI.Message
              { OpenAI.msgRole = fromAnthropicRole respRole,
                OpenAI.msgContent = Just $ OpenAI.TextContent $ extractTextContent respContent,
                OpenAI.msgName = Nothing,
                OpenAI.msgToolCallId = Nothing,
                OpenAI.msgToolCalls = Nothing -- Would need tool call conversion
              },
          OpenAI.choiceFinishReason = Just $ OpenAI.FinishReason $ fromStopReason respStopReason
        }

-- | Extract text from content blocks
extractTextContent :: [A.ContentBlock] -> Text
extractTextContent blocks = T.concat [t | A.TextBlock t <- blocks]

-- | Convert role back to OpenAI format
fromAnthropicRole :: A.Role -> OpenAI.Role
fromAnthropicRole A.User = OpenAI.User
fromAnthropicRole A.Assistant = OpenAI.Assistant
fromAnthropicRole A.System = OpenAI.System

-- | Convert stop reason to OpenAI format
fromStopReason :: Maybe A.StopReason -> Text
fromStopReason Nothing = "stop"
fromStopReason (Just A.EndTurn) = "stop"
fromStopReason (Just A.MaxTokens) = "length"
fromStopReason (Just A.ToolUseSR) = "tool_calls"
fromStopReason (Just A.StopSequence) = "stop"

-- | Convert usage stats
fromAnthropicUsage :: A.Usage -> OpenAI.Usage
fromAnthropicUsage A.Usage {..} =
  OpenAI.Usage
    { OpenAI.usagePromptTokens = usageInputTokens,
      OpenAI.usageCompletionTokens = usageOutputTokens,
      OpenAI.usageTotalTokens = usageInputTokens + usageOutputTokens
    }

-- ════════════════════════════════════════════════════════════════════════════
--                                                         // tool accumulation
-- ════════════════════════════════════════════════════════════════════════════

-- | Active tool call being accumulated from streaming events
--
-- Anthropic streams tool calls as:
-- 1. content_block_start with tool_use block (provides id, name)
-- 2. content_block_delta with input_json_delta (provides partial JSON)
-- 3. content_block_stop (signals completion)
--
-- We accumulate the JSON fragments and emit a complete ToolUse when the
-- block stops.
data ActiveToolCall = ActiveToolCall
    { atcId :: !Text
    -- ^ Tool call ID (e.g., "toolu_01...")
    , atcName :: !Text
    -- ^ Tool name (e.g., "get_weather")
    , atcInputJson :: !Text
    -- ^ Accumulated JSON input (concatenated partial_json fragments)
    }

-- | Tool call accumulation state
--
-- Maps content block index to active tool call.
type ToolCallAccumulator = Map Int ActiveToolCall

-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // http
-- ════════════════════════════════════════════════════════════════════════════

-- | Anthropic API version header
anthropicVersion :: ByteString
anthropicVersion = "2023-06-01"

-- | Make a POST request with Anthropic-specific headers
makeRequest :: HC.Manager -> String -> Text -> LBS.ByteString -> IO (Either (Int, Text) LBS.ByteString)
makeRequest manager url apiKey body = do
  result <- try @HttpException $ do
    initReq <- HC.parseRequest url
    let req =
          initReq
            { HC.method = "POST",
              HC.requestHeaders =
                [ ("Content-Type", "application/json"),
                  ("x-api-key", encodeUtf8 apiKey),
                  ("anthropic-version", anthropicVersion)
                ],
              HC.requestBody = HC.RequestBodyLBS body
            }
    HC.httpLbs req manager

  case result of
    Left e -> pure $ Left (0, T.pack $ show e)
    Right resp -> do
      let status = HT.statusCode $ HC.responseStatus resp
      if status >= 200 && status < 300
        then pure $ Right $ HC.responseBody resp
        else pure $ Left (status, decodeBody $ HC.responseBody resp)

-- | Make a streaming POST request (raw bytes to callback)
makeStreamingRequest :: HC.Manager -> String -> Text -> LBS.ByteString -> StreamCallback -> IO (Either (Int, Text) ())
makeStreamingRequest manager url apiKey body callback = do
  result <- try @HttpException $ do
    initReq <- HC.parseRequest url
    let req =
          initReq
            { HC.method = "POST",
              HC.requestHeaders =
                [ ("Content-Type", "application/json"),
                  ("x-api-key", encodeUtf8 apiKey),
                  ("anthropic-version", anthropicVersion)
                ],
              HC.requestBody = HC.RequestBodyLBS body
            }
    HC.withResponse req manager $ \resp -> do
      let status = HT.statusCode $ HC.responseStatus resp
      if status >= 200 && status < 300
        then do
          streamBody (HC.responseBody resp) callback
          pure $ Right ()
        else do
          body' <- HC.brConsume $ HC.responseBody resp
          pure $ Left (status, decodeBody $ LBS.fromChunks body')

  case result of
    Left e -> pure $ Left (0, T.pack $ show e)
    Right r -> pure r

-- | Make a streaming request with SSE parsing for tool accumulation
makeStreamingRequestWithParsing ::
  HC.Manager ->
  String ->
  Text ->
  LBS.ByteString ->
  -- | Content delta handler
  (Text -> IO ()) ->
  -- | Accumulated tool calls
  IORef [A.ToolUse] ->
  IORef (Maybe A.StopReason) ->
  IORef (Maybe A.Usage) ->
  IO (Either (Int, Text) ())
makeStreamingRequestWithParsing manager url apiKey body onDelta toolCallsRef stopReasonRef usageRef = do
  -- Create tool call accumulator for tracking in-flight tool calls
  toolCallAccumRef <- newIORef (Map.empty :: ToolCallAccumulator)
  
  result <- try @HttpException $ do
    initReq <- HC.parseRequest url
    let req =
          initReq
            { HC.method = "POST",
              HC.requestHeaders =
                [ ("Content-Type", "application/json"),
                  ("x-api-key", encodeUtf8 apiKey),
                  ("anthropic-version", anthropicVersion)
                ],
              HC.requestBody = HC.RequestBodyLBS body
            }
    HC.withResponse req manager $ \resp -> do
      let status = HT.statusCode $ HC.responseStatus resp
      if status >= 200 && status < 300
        then do
          streamBodyWithParsing (HC.responseBody resp) onDelta toolCallsRef toolCallAccumRef stopReasonRef usageRef
          pure $ Right ()
        else do
          body' <- HC.brConsume $ HC.responseBody resp
          pure $ Left (status, decodeBody $ LBS.fromChunks body')

  case result of
    Left e -> pure $ Left (0, T.pack $ show e)
    Right r -> pure r

-- | Stream response body chunks (raw)
streamBody :: HC.BodyReader -> StreamCallback -> IO ()
streamBody bodyReader callback = loop
  where
    loop = do
      chunk <- HC.brRead bodyReader
      if BS.null chunk
        then pure ()
        else do
          callback chunk
          loop

-- | Stream body with SSE parsing for Anthropic events
streamBodyWithParsing ::
  HC.BodyReader ->
  (Text -> IO ()) ->
  IORef [A.ToolUse] ->
  IORef ToolCallAccumulator ->
  IORef (Maybe A.StopReason) ->
  IORef (Maybe A.Usage) ->
  IO ()
streamBodyWithParsing bodyReader onDelta toolCallsRef toolCallAccumRef stopReasonRef usageRef = loop ""
  where
    loop :: Text -> IO ()
    loop buffer = do
      chunk <- HC.brRead bodyReader
      if BS.null chunk
        then do
          _ <- processBuffer buffer -- Process remaining buffer, discard remainder
          pure ()
        else do
          let newBuffer = buffer <> decodeUtf8 chunk
          remaining <- processBuffer newBuffer
          loop remaining

    -- Process complete SSE lines from buffer, return incomplete remainder
    processBuffer :: Text -> IO Text
    processBuffer buf =
      case T.breakOn "\n" buf of
        (line, rest)
          | T.null rest -> pure buf -- No newline, buffer incomplete
          | otherwise -> do
              processLine line
              processBuffer (T.drop 1 rest) -- Skip the newline

    -- Process a single SSE line
    processLine :: Text -> IO ()
    processLine line
      | "data: " `T.isPrefixOf` line = do
          let jsonPart = T.drop 6 line
          parseAnthropicEvent jsonPart onDelta toolCallsRef toolCallAccumRef stopReasonRef usageRef
      | otherwise = pure () -- Skip event: lines and empty lines

-- | Parse Anthropic SSE event using typed StreamEvent and dispatch
--
-- Uses the properly typed StreamEvent ADT with full FromJSON instance
-- instead of ad-hoc Value parsing. This ensures type safety and makes
-- the parsing verifiable.
parseAnthropicEvent ::
  Text ->
  (Text -> IO ()) ->
  IORef [A.ToolUse] ->
  IORef ToolCallAccumulator ->
  IORef (Maybe A.StopReason) ->
  IORef (Maybe A.Usage) ->
  IO ()
parseAnthropicEvent jsonText onDelta toolCallsRef toolCallAccumRef stopReasonRef usageRef = do
  let mEvent = Aeson.decode (LBS.fromStrict $ encodeUtf8 jsonText) :: Maybe A.StreamEvent
  case mEvent of
    Nothing -> pure () -- Unparseable, skip
    Just event -> handleStreamEvent event onDelta toolCallsRef toolCallAccumRef stopReasonRef usageRef

-- | Handle a typed StreamEvent
handleStreamEvent ::
  A.StreamEvent ->
  (Text -> IO ()) ->
  IORef [A.ToolUse] ->
  IORef ToolCallAccumulator ->
  IORef (Maybe A.StopReason) ->
  IORef (Maybe A.Usage) ->
  IO ()
handleStreamEvent event onDelta toolCallsRef toolCallAccumRef stopReasonRef usageRef = case event of
  A.EventContentBlockDelta cbde ->
    handleContentBlockDelta cbde toolCallAccumRef onDelta
  A.EventMessageDelta mde ->
    handleMessageDelta mde stopReasonRef usageRef
  A.EventMessageStart mse ->
    handleMessageStart mse usageRef
  A.EventContentBlockStart idx block ->
    handleContentBlockStart idx block toolCallAccumRef
  A.EventContentBlockStop idx ->
    handleContentBlockStop idx toolCallsRef toolCallAccumRef
  A.EventMessageStop -> pure () -- Stream complete
  A.EventPing -> pure () -- Keepalive
  A.EventError _msg -> pure () -- Errors logged at higher level

-- | Handle content_block_start event
--
-- If this is a tool_use block, start accumulating the tool call.
handleContentBlockStart :: Int -> A.ContentBlock -> IORef ToolCallAccumulator -> IO ()
handleContentBlockStart idx block toolCallAccumRef = case block of
  A.ToolUseBlock toolUse -> do
    let activeCall = ActiveToolCall
            { atcId = A.tuId toolUse
            , atcName = A.tuName toolUse
            , atcInputJson = ""  -- Will be filled by input_json_delta events
            }
    modifyIORef' toolCallAccumRef (Map.insert idx activeCall)
  _ -> pure ()  -- Text blocks, image blocks, etc. don't need accumulation

-- | Handle content_block_delta event (typed)
handleContentBlockDelta :: A.ContentBlockDeltaEvent -> IORef ToolCallAccumulator -> (Text -> IO ()) -> IO ()
handleContentBlockDelta A.ContentBlockDeltaEvent {..} toolCallAccumRef onDelta =
  case cbdeDelta of
    A.TextDelta t -> onDelta t
    A.InputJsonDelta partial -> do
      -- Accumulate partial JSON into the active tool call
      modifyIORef' toolCallAccumRef $ \accum ->
        case Map.lookup cbdeIndex accum of
          Just activeCall ->
            let updatedCall = activeCall { atcInputJson = atcInputJson activeCall <> partial }
             in Map.insert cbdeIndex updatedCall accum
          Nothing ->
            -- No active tool call for this index - shouldn't happen
            accum

-- | Handle content_block_stop event
--
-- If there's an active tool call for this block, finalize it and add to results.
handleContentBlockStop :: Int -> IORef [A.ToolUse] -> IORef ToolCallAccumulator -> IO ()
handleContentBlockStop idx toolCallsRef toolCallAccumRef = do
  accum <- readIORef toolCallAccumRef
  case Map.lookup idx accum of
    Just activeCall -> do
      -- Parse accumulated JSON into ToolInput
      let inputJson = atcInputJson activeCall
          toolInput = case Aeson.decode (LBS.fromStrict $ encodeUtf8 inputJson) of
            Just obj -> A.ToolInputObject obj
            Nothing -> A.ToolInputEmpty  -- Failed to parse - use empty
      
      let toolUse = A.ToolUse
            { A.tuId = atcId activeCall
            , A.tuName = atcName activeCall
            , A.tuInput = toolInput
            }
      
      -- Add to completed tool calls
      modifyIORef' toolCallsRef (toolUse :)
      
      -- Remove from accumulator
      modifyIORef' toolCallAccumRef (Map.delete idx)
    
    Nothing ->
      -- No active tool call for this block (was probably text)
      pure ()

-- | Handle message_delta event (typed)
handleMessageDelta :: A.MessageDeltaEvent -> IORef (Maybe A.StopReason) -> IORef (Maybe A.Usage) -> IO ()
handleMessageDelta A.MessageDeltaEvent {..} stopReasonRef usageRef = do
  case mdeStopReason of
    Just sr -> modifyIORef' stopReasonRef (const (Just sr))
    Nothing -> pure ()
  case mdeUsage of
    Just u -> modifyIORef' usageRef (const (Just u))
    Nothing -> pure ()

-- | Handle message_start event (typed)
handleMessageStart :: A.MessageStartEvent -> IORef (Maybe A.Usage) -> IO ()
handleMessageStart A.MessageStartEvent {..} usageRef = do
  let usage = A.respUsage mseMessage
  modifyIORef' usageRef (const (Just usage))

-- | Decode response body to text
decodeBody :: LBS.ByteString -> Text
decodeBody = decodeUtf8 . LBS.toStrict

-- | Classify HTTP error into ProviderError
classifyError :: (Int, Text) -> ProviderResult a
classifyError (status, msg)
  | status == 401 = Failure $ AuthError msg
  | status == 429 = Retry $ RateLimitError msg
  | status == 402 = Failure $ QuotaExceededError msg -- Credits exhausted is terminal, not transient
  | status == 404 = Retry $ ModelNotFoundError msg -- Model not found should try next provider
  | status == 529 = Retry $ ProviderUnavailable msg -- Anthropic overloaded
  | status >= 500 = Retry $ ProviderUnavailable msg
  | status >= 400 = Failure $ InvalidRequestError msg
  | status == 0 = Retry $ TimeoutError msg
  | otherwise = Failure $ UnknownError msg
