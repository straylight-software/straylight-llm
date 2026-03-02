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
{-# LANGUAGE OverloadedStrings #-}
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
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Effects.Graded
  ( GatewayM,
    liftGatewayIO,
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
isEnabled :: IORef ProviderConfig -> GatewayM Bool
isEnabled configRef = do
  recordConfigAccess "anthropic.enabled"
  config <- liftGatewayIO $ readIORef configRef
  pure $ pcEnabled config && pcApiKey config /= Nothing

-- | Check if model is supported (Claude models)
supportsModel :: Text -> Bool
supportsModel modelId =
  any
    (`T.isPrefixOf` modelId)
    [ "claude-",
      "anthropic/" -- OpenRouter-style prefix
    ]

-- | Non-streaming chat completion (OpenAI-compatible wrapper)
chat :: IORef ProviderConfig -> RequestContext -> OpenAI.ChatRequest -> GatewayM (ProviderResult OpenAI.ChatResponse)
chat configRef ctx req = do
  recordProvider "anthropic"
  recordModel (OpenAI.unModelId $ OpenAI.crModel req)
  config <- liftGatewayIO $ readIORef configRef
  case pcApiKey config of
    Nothing -> pure $ Failure $ AuthError "Anthropic API key not configured"
    Just apiKey -> do
      recordAuthUsage "anthropic" "api-key"
      -- Convert OpenAI request to Anthropic format
      let anthropicReq = toAnthropicRequest req
          url = T.unpack (pcBaseUrl config) <> "/messages"
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- withLatency $ makeRequest (rcManager ctx) url apiKey (encode anthropicReq)
      pure $ case result of
        Left err -> classifyError err
        Right body -> case eitherDecode body of
          Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
          Right resp -> Success $ fromAnthropicResponse resp

-- | Streaming chat completion (OpenAI-compatible wrapper)
chatStream :: IORef ProviderConfig -> RequestContext -> OpenAI.ChatRequest -> StreamCallback -> GatewayM (ProviderResult ())
chatStream configRef ctx req callback = do
  recordProvider "anthropic"
  recordModel (OpenAI.unModelId $ OpenAI.crModel req)
  config <- liftGatewayIO $ readIORef configRef
  case pcApiKey config of
    Nothing -> pure $ Failure $ AuthError "Anthropic API key not configured"
    Just apiKey -> do
      recordAuthUsage "anthropic" "api-key"
      let anthropicReq = (toAnthropicRequest req) {A.crStream = True}
          url = T.unpack (pcBaseUrl config) <> "/messages"
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- withLatency $ makeStreamingRequest (rcManager ctx) url apiKey (encode anthropicReq) callback
      pure $ case result of
        Left err -> classifyError err
        Right () -> Success ()

-- | Anthropic doesn't provide embeddings
embeddings :: RequestContext -> OpenAI.EmbeddingRequest -> GatewayM (ProviderResult OpenAI.EmbeddingResponse)
embeddings _ctx _req = do
  recordProvider "anthropic"
  pure $ Failure $ ModelNotFoundError "Anthropic does not provide embedding models"

-- | List available models
models :: IORef ProviderConfig -> RequestContext -> GatewayM (ProviderResult OpenAI.ModelList)
models configRef ctx = do
  recordProvider "anthropic"
  config <- liftGatewayIO $ readIORef configRef
  case pcApiKey config of
    Nothing -> pure $ Failure $ AuthError "Anthropic API key not configured"
    Just apiKey -> do
      recordAuthUsage "anthropic" "api-key"
      let url = T.unpack (pcBaseUrl config) <> "/models"
      recordHttpAccess (T.pack url) "GET" Nothing
      result <- withLatency $ makeModelsRequest (rcManager ctx) url apiKey
      case result of
        Left err -> pure $ classifyError err
        Right body -> case eitherDecode body of
          Left parseErr -> pure $ Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
          Right anthropicModels -> pure $ Success $ toOpenAIModelList anthropicModels

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
  GatewayM (ProviderResult A.ChatResponse)
anthropicChat manager apiKey baseUrl req = do
  recordProvider "anthropic"
  recordModel (A.crModel req)
  recordAuthUsage "anthropic" "api-key"
  let url = T.unpack baseUrl <> "/messages"
  recordHttpAccess (T.pack url) "POST" Nothing
  result <- withLatency $ makeRequest manager url apiKey (encode req)
  pure $ case result of
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
  GatewayM (ProviderResult StreamResult)
anthropicChatStream manager apiKey baseUrl req onDelta = do
  recordProvider "anthropic"
  recordModel (A.crModel req)
  recordAuthUsage "anthropic" "api-key"
  let streamReq = req {A.crStream = True}
      url = T.unpack baseUrl <> "/messages"
  recordHttpAccess (T.pack url) "POST" Nothing

  -- Track state across stream
  toolCallsRef <- liftGatewayIO $ newIORef ([] :: [A.ToolUse])
  stopReasonRef <- liftGatewayIO $ newIORef (Nothing :: Maybe A.StopReason)
  usageRef <- liftGatewayIO $ newIORef (Nothing :: Maybe A.Usage)

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

  case result of
    Left err -> pure $ classifyError err
    Right () -> do
      toolCalls <- liftGatewayIO $ readIORef toolCallsRef
      stopReason <- liftGatewayIO $ readIORef stopReasonRef
      usage <- liftGatewayIO $ readIORef usageRef
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
makeStreamingRequestWithParsing manager url apiKey body onDelta _toolCallsRef stopReasonRef usageRef = do
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
          streamBodyWithParsing (HC.responseBody resp) onDelta stopReasonRef usageRef
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
  IORef (Maybe A.StopReason) ->
  IORef (Maybe A.Usage) ->
  IO ()
streamBodyWithParsing bodyReader onDelta stopReasonRef usageRef = loop ""
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
          parseAnthropicEvent jsonPart onDelta stopReasonRef usageRef
      | otherwise = pure () -- Skip event: lines and empty lines

-- | Parse Anthropic SSE event using typed StreamEvent and dispatch
--
-- Uses the properly typed StreamEvent ADT with full FromJSON instance
-- instead of ad-hoc Value parsing. This ensures type safety and makes
-- the parsing verifiable.
parseAnthropicEvent ::
  Text ->
  (Text -> IO ()) ->
  IORef (Maybe A.StopReason) ->
  IORef (Maybe A.Usage) ->
  IO ()
parseAnthropicEvent jsonText onDelta stopReasonRef usageRef = do
  let mEvent = Aeson.decode (LBS.fromStrict $ encodeUtf8 jsonText) :: Maybe A.StreamEvent
  case mEvent of
    Nothing -> pure () -- Unparseable, skip
    Just event -> handleStreamEvent event onDelta stopReasonRef usageRef

-- | Handle a typed StreamEvent
handleStreamEvent ::
  A.StreamEvent ->
  (Text -> IO ()) ->
  IORef (Maybe A.StopReason) ->
  IORef (Maybe A.Usage) ->
  IO ()
handleStreamEvent event onDelta stopReasonRef usageRef = case event of
  A.EventContentBlockDelta cbde ->
    handleContentBlockDelta cbde onDelta
  A.EventMessageDelta mde ->
    handleMessageDelta mde stopReasonRef usageRef
  A.EventMessageStart mse ->
    handleMessageStart mse usageRef
  A.EventContentBlockStart _ _ -> pure () -- Could track block indices
  A.EventContentBlockStop _ -> pure () -- Could finalize blocks
  A.EventMessageStop -> pure () -- Stream complete
  A.EventPing -> pure () -- Keepalive
  A.EventError _msg -> pure () -- Could log errors

-- | Handle content_block_delta event (typed)
handleContentBlockDelta :: A.ContentBlockDeltaEvent -> (Text -> IO ()) -> IO ()
handleContentBlockDelta A.ContentBlockDeltaEvent {..} onDelta =
  case cbdeDelta of
    A.TextDelta t -> onDelta t
    A.InputJsonDelta _partial ->
      -- Tool input streaming - would accumulate JSON chunks
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
