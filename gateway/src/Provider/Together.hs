-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                     // straylight-llm // provider/together
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The sky above the port was the color of television, tuned to a dead
--      channel."
--
--                                                              — Neuromancer
--
-- Together AI provider. High-throughput inference with NO RATE LIMITS.
-- OpenAI-compatible API. Optimal for open models at scale.
--
-- API: https://api.together.xyz/v1
-- Docs: https://docs.together.ai
--
-- Key advantages:
--   • No rate limits - pay per token
--   • Fast inference optimized for throughput
--   • Excellent open model coverage (Llama, Mixtral, etc.)
--   • OpenAI-compatible API format
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.Together
  ( -- * Provider
    makeTogetherProvider,
  )
where

import Config (ProviderConfig (pcApiKey, pcBaseUrl, pcEnabled))
import Control.Exception (try)
import Data.Aeson (eitherDecode, encode)
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Effects.Do qualified as G
import Effects.Graded (Full, GatewayM, liftIO', recordAuthUsage, recordConfigAccess, recordHttpAccess)
import Network.HTTP.Client (HttpException)
import Network.HTTP.Client qualified as HC
import Network.HTTP.Types qualified as HT
import Provider.Types
  ( Provider
      ( Provider,
        providerChat,
        providerChatStream,
        providerEmbeddings,
        providerEnabled,
        providerModels,
        providerName,
        providerSupportsModel
      ),
    ProviderError (AuthError, InternalError, InvalidRequestError, ProviderUnavailable, RateLimitError, TimeoutError),
    ProviderName (Together),
    ProviderResult (Failure, Retry, Success),
    RequestContext (rcManager, rcRequestId),
    StreamCallback,
  )
import Types
  ( ChatRequest,
    ChatResponse,
    EmbeddingRequest,
    EmbeddingResponse,
    Model (Model),
    ModelId (ModelId),
    ModelList (ModelList),
  )

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // constants
-- ════════════════════════════════════════════════════════════════════════════

-- | Default Together API base URL
defaultBaseUrl :: Text
defaultBaseUrl = "https://api.together.xyz"

-- | Models supported by Together AI (subset - they have many more)
togetherModels :: [Text]
togetherModels =
  [ -- Llama 3.x
    "meta-llama/Meta-Llama-3.1-405B-Instruct-Turbo",
    "meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo",
    "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo",
    "meta-llama/Llama-3.2-90B-Vision-Instruct-Turbo",
    "meta-llama/Llama-3.2-11B-Vision-Instruct-Turbo",
    "meta-llama/Llama-3.2-3B-Instruct-Turbo",
    -- Mixtral
    "mistralai/Mixtral-8x22B-Instruct-v0.1",
    "mistralai/Mixtral-8x7B-Instruct-v0.1",
    "mistralai/Mistral-7B-Instruct-v0.3",
    -- Qwen
    "Qwen/Qwen2.5-72B-Instruct-Turbo",
    "Qwen/Qwen2.5-7B-Instruct-Turbo",
    "Qwen/QwQ-32B-Preview",
    -- DeepSeek
    "deepseek-ai/DeepSeek-R1-Distill-Llama-70B",
    "deepseek-ai/DeepSeek-V3",
    -- Code
    "Qwen/Qwen2.5-Coder-32B-Instruct",
    "meta-llama/Llama-3.3-70B-Instruct-Turbo"
  ]

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | Create Together AI provider
makeTogetherProvider :: IORef ProviderConfig -> Provider
makeTogetherProvider configRef =
  Provider
    { providerName = Together,
      providerEnabled = isEnabled configRef,
      providerChat = chatCompletion configRef,
      providerChatStream = chatCompletionStream configRef,
      providerEmbeddings = embeddings configRef,
      providerModels = listModels configRef,
      providerSupportsModel = supportsModel
    }

-- | Check if Together is configured and enabled
isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "together.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing

-- | Check if model is supported
supportsModel :: Text -> Bool
supportsModel modelId =
  modelId `elem` togetherModels
    || "meta-llama" `T.isInfixOf` modelId
    || "mistralai" `T.isInfixOf` modelId
    || "Qwen" `T.isInfixOf` modelId
    || "deepseek" `T.isInfixOf` modelId

-- ════════════════════════════════════════════════════════════════════════════
--                                                          // chat completion
-- ═══════════════════════════════════��════════════════════════════════════════

-- | Non-streaming chat completion
chatCompletion ::
  IORef ProviderConfig ->
  RequestContext ->
  ChatRequest ->
  GatewayM Full (ProviderResult ChatResponse)
chatCompletion configRef ctx req = G.do
  recordAuthUsage "together" Nothing
  config <- liftIO' $ readIORef configRef

  let baseUrl = maybe defaultBaseUrl id (pcBaseUrl config)
      url = T.unpack baseUrl <> "/v1/chat/completions"
      apiKey = maybe "" id (pcApiKey config)

  recordHttpAccess url "POST"

  result <- liftIO' $ do
    initReq <- HC.parseRequest url
    let httpReq =
          initReq
            { HC.method = "POST",
              HC.requestHeaders =
                [ ("Authorization", "Bearer " <> encodeUtf8 apiKey),
                  ("Content-Type", "application/json"),
                  ("X-Request-ID", encodeUtf8 $ rcRequestId ctx)
                ],
              HC.requestBody = HC.RequestBodyLBS (encode req)
            }

    tryResult <- try @HttpException $ HC.httpLbs httpReq (rcManager ctx)
    pure $ case tryResult of
      Left e -> Left $ ProviderUnavailable $ T.pack $ show e
      Right resp -> Right resp

  case result of
    Left err -> liftIO' $ pure $ Retry err
    Right resp -> liftIO' $ do
      let status = HT.statusCode $ HC.responseStatus resp
          body = HC.responseBody resp
      pure $ handleResponse status body

-- | Streaming chat completion
chatCompletionStream ::
  IORef ProviderConfig ->
  RequestContext ->
  ChatRequest ->
  StreamCallback ->
  GatewayM Full (ProviderResult ())
chatCompletionStream configRef ctx req callback = G.do
  recordAuthUsage "together" Nothing
  config <- liftIO' $ readIORef configRef

  let baseUrl = maybe defaultBaseUrl id (pcBaseUrl config)
      url = T.unpack baseUrl <> "/v1/chat/completions"
      apiKey = maybe "" id (pcApiKey config)

  recordHttpAccess url "POST"

  result <- liftIO' $ do
    initReq <- HC.parseRequest url
    let httpReq =
          initReq
            { HC.method = "POST",
              HC.requestHeaders =
                [ ("Authorization", "Bearer " <> encodeUtf8 apiKey),
                  ("Content-Type", "application/json"),
                  ("Accept", "text/event-stream"),
                  ("X-Request-ID", encodeUtf8 $ rcRequestId ctx)
                ],
              HC.requestBody = HC.RequestBodyLBS (encode req)
            }

    tryResult <- try @HttpException $ HC.withResponse httpReq (rcManager ctx) $ \resp -> do
      let status = HT.statusCode $ HC.responseStatus resp
      if status >= 200 && status < 300
        then do
          streamBody (HC.responseBody resp) callback
          pure $ Right ()
        else do
          body <- HC.brConsume (HC.responseBody resp)
          pure $ Left $ handleErrorStatus status (LBS.fromChunks body)

    pure $ case tryResult of
      Left e -> Left $ ProviderUnavailable $ T.pack $ show e
      Right r -> r

  case result of
    Left err -> liftIO' $ pure $ Retry err
    Right () -> liftIO' $ pure $ Success ()

-- | Stream response body, calling callback for each SSE chunk
streamBody :: HC.BodyReader -> StreamCallback -> IO ()
streamBody bodyReader callback = go
  where
    go = do
      chunk <- HC.brRead bodyReader
      if chunk == ""
        then pure ()
        else do
          callback chunk
          go

-- ════════════════════════════════════════════════════════════════════════════
--                                                               // embeddings
-- ════════════════════════════════════════════════════════════════════════════

-- | Embeddings (Together supports embeddings too)
embeddings ::
  IORef ProviderConfig ->
  RequestContext ->
  EmbeddingRequest ->
  GatewayM Full (ProviderResult EmbeddingResponse)
embeddings configRef ctx req = G.do
  recordAuthUsage "together" Nothing
  config <- liftIO' $ readIORef configRef

  let baseUrl = maybe defaultBaseUrl id (pcBaseUrl config)
      url = T.unpack baseUrl <> "/v1/embeddings"
      apiKey = maybe "" id (pcApiKey config)

  recordHttpAccess url "POST"

  result <- liftIO' $ do
    initReq <- HC.parseRequest url
    let httpReq =
          initReq
            { HC.method = "POST",
              HC.requestHeaders =
                [ ("Authorization", "Bearer " <> encodeUtf8 apiKey),
                  ("Content-Type", "application/json")
                ],
              HC.requestBody = HC.RequestBodyLBS (encode req)
            }

    tryResult <- try @HttpException $ HC.httpLbs httpReq (rcManager ctx)
    pure $ case tryResult of
      Left e -> Left $ ProviderUnavailable $ T.pack $ show e
      Right resp -> Right resp

  case result of
    Left err -> liftIO' $ pure $ Retry err
    Right resp -> liftIO' $ do
      let status = HT.statusCode $ HC.responseStatus resp
          body = HC.responseBody resp
      pure $ case status of
        s | s >= 200 && s < 300 ->
          case eitherDecode body of
            Left e -> Failure $ InternalError $ "Parse error: " <> T.pack e
            Right r -> Success r
        s -> handleErrorStatus s body

-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // models
-- ════════════════════════════════════════════════════════════════════════════

-- | List available models
listModels ::
  IORef ProviderConfig ->
  RequestContext ->
  GatewayM Full (ProviderResult ModelList)
listModels configRef ctx = G.do
  recordAuthUsage "together" Nothing
  config <- liftIO' $ readIORef configRef

  let baseUrl = maybe defaultBaseUrl id (pcBaseUrl config)
      url = T.unpack baseUrl <> "/v1/models"
      apiKey = maybe "" id (pcApiKey config)

  recordHttpAccess url "GET"

  result <- liftIO' $ do
    initReq <- HC.parseRequest url
    let httpReq =
          initReq
            { HC.method = "GET",
              HC.requestHeaders =
                [ ("Authorization", "Bearer " <> encodeUtf8 apiKey),
                  ("Accept", "application/json")
                ]
            }

    tryResult <- try @HttpException $ HC.httpLbs httpReq (rcManager ctx)
    pure $ case tryResult of
      Left e -> Left $ ProviderUnavailable $ T.pack $ show e
      Right resp -> Right resp

  case result of
    Left err -> liftIO' $ pure $ Retry err
    Right resp -> liftIO' $ do
      let status = HT.statusCode $ HC.responseStatus resp
          body = HC.responseBody resp
      pure $ case status of
        s | s >= 200 && s < 300 ->
          case eitherDecode body of
            Left _ ->
              -- Fallback to hardcoded models if API doesn't return proper format
              Success $ ModelList "list" $ map makeModel togetherModels
            Right r -> Success r
        s -> handleErrorStatus s body
  where
    makeModel mid = Model (ModelId mid) "model" (Timestamp 0) "together"

-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Handle successful response
handleResponse :: Int -> LBS.ByteString -> ProviderResult ChatResponse
handleResponse status body
  | status >= 200 && status < 300 =
      case eitherDecode body of
        Left e -> Failure $ InternalError $ "Parse error: " <> T.pack e
        Right r -> Success r
  | otherwise = handleErrorStatus status body

-- | Handle error status codes
handleErrorStatus :: Int -> LBS.ByteString -> ProviderResult a
handleErrorStatus status body = case status of
  401 -> Failure $ AuthError "Invalid Together API key"
  403 -> Failure $ AuthError "Together API key lacks permissions"
  429 -> Retry $ RateLimitError "Together rate limit (unexpected - they have no limits)"
  408 -> Retry $ TimeoutError "Together request timeout"
  500 -> Retry $ InternalError $ "Together 500: " <> bodyText
  502 -> Retry $ ProviderUnavailable "Together 502 Bad Gateway"
  503 -> Retry $ ProviderUnavailable "Together 503 Service Unavailable"
  504 -> Retry $ TimeoutError "Together 504 Gateway Timeout"
  _ -> Failure $ InvalidRequestError $ "Together " <> T.pack (show status) <> ": " <> bodyText
  where
    bodyText = T.take 500 $ T.pack $ show body
