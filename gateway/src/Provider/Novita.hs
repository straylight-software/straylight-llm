-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                       // straylight-llm // provider/novita
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Case had never seen him wear the same suit twice."
--
--                                                              — Neuromancer
--
-- Novita AI provider. NO RATE LIMITS. Pay-per-use inference.
-- OpenAI-compatible API. Excellent for burst capacity.
--
-- API: https://api.novita.ai/v3/openai
-- Docs: https://novita.ai/docs
--
-- Key advantages:
--   • NO RATE LIMITS - truly unlimited throughput
--   • Pay-per-token pricing
--   • OpenAI-compatible API
--   • Good open model coverage
--   • Fast cold starts
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.Novita
  ( -- * Provider
    makeNovitaProvider,
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
    ProviderName (Novita),
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
    Timestamp (Timestamp),
  )

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // constants
-- ════════════════════════════════════════════════════════════════════════════

-- | Default Novita API base URL
defaultBaseUrl :: Text
defaultBaseUrl = "https://api.novita.ai/v3/openai"

-- | Models supported by Novita AI
novitaModels :: [Text]
novitaModels =
  [ -- Llama 3.x
    "meta-llama/llama-3.1-405b-instruct",
    "meta-llama/llama-3.1-70b-instruct",
    "meta-llama/llama-3.1-8b-instruct",
    "meta-llama/llama-3.2-3b-instruct",
    "meta-llama/llama-3.3-70b-instruct",
    -- Qwen
    "qwen/qwen-2.5-72b-instruct",
    "qwen/qwen-2.5-32b-instruct",
    "qwen/qwen-2.5-coder-32b-instruct",
    "qwen/qwq-32b-preview",
    -- Mixtral
    "mistralai/mixtral-8x22b-instruct",
    "mistralai/mixtral-8x7b-instruct",
    "mistralai/mistral-7b-instruct",
    -- DeepSeek
    "deepseek/deepseek-v3",
    "deepseek/deepseek-r1",
    "deepseek/deepseek-coder-33b-instruct",
    -- Others
    "google/gemma-2-27b-it",
    "microsoft/phi-3-medium-128k-instruct"
  ]

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | Create Novita AI provider
makeNovitaProvider :: IORef ProviderConfig -> Provider
makeNovitaProvider configRef =
  Provider
    { providerName = Novita,
      providerEnabled = isEnabled configRef,
      providerChat = chatCompletion configRef,
      providerChatStream = chatCompletionStream configRef,
      providerEmbeddings = embeddings configRef,
      providerModels = listModels configRef,
      providerSupportsModel = supportsModel
    }

-- | Check if Novita is configured and enabled
isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "novita.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing

-- | Check if model is supported
supportsModel :: Text -> Bool
supportsModel modelId =
  modelId `elem` novitaModels
    || "llama" `T.isInfixOf` T.toLower modelId
    || "mistral" `T.isInfixOf` T.toLower modelId
    || "qwen" `T.isInfixOf` T.toLower modelId
    || "deepseek" `T.isInfixOf` T.toLower modelId

-- ════════════════════════════════════════════════════════════════════════════
--                                                          // chat completion
-- ════════════════════════════════════════════════════════════════════════════

-- | Non-streaming chat completion
chatCompletion ::
  IORef ProviderConfig ->
  RequestContext ->
  ChatRequest ->
  GatewayM Full (ProviderResult ChatResponse)
chatCompletion configRef ctx req = G.do
  recordAuthUsage "novita" "api-key"
  config <- liftIO' $ readIORef configRef

  let baseUrl = if T.null (pcBaseUrl config) then defaultBaseUrl else pcBaseUrl config
      url = T.unpack baseUrl <> "/chat/completions"
      apiKey = maybe "" id (pcApiKey config)

  recordHttpAccess (T.pack url) "POST" Nothing

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
  recordAuthUsage "novita" "api-key"
  config <- liftIO' $ readIORef configRef

  let baseUrl = if T.null (pcBaseUrl config) then defaultBaseUrl else pcBaseUrl config
      url = T.unpack baseUrl <> "/chat/completions"
      apiKey = maybe "" id (pcApiKey config)

  recordHttpAccess (T.pack url) "POST" Nothing

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
          pure Nothing
        else do
          body <- HC.brConsume (HC.responseBody resp)
          pure $ Just $ handleErrorStatus status (LBS.fromChunks body)

    pure $ case tryResult of
      Left e -> Retry $ ProviderUnavailable $ T.pack $ show e
      Right Nothing -> Success ()
      Right (Just provResult) -> provResult

  liftIO' $ pure result

-- | Stream response body
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

-- | Embeddings
embeddings ::
  IORef ProviderConfig ->
  RequestContext ->
  EmbeddingRequest ->
  GatewayM Full (ProviderResult EmbeddingResponse)
embeddings configRef ctx req = G.do
  recordAuthUsage "novita" "api-key"
  config <- liftIO' $ readIORef configRef

  let baseUrl = if T.null (pcBaseUrl config) then defaultBaseUrl else pcBaseUrl config
      url = T.unpack baseUrl <> "/embeddings"
      apiKey = maybe "" id (pcApiKey config)

  recordHttpAccess (T.pack url) "POST" Nothing

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
listModels _configRef _ctx = G.do
  -- Novita doesn't have a models endpoint, return hardcoded list
  liftIO' $ pure $ Success $ ModelList "list" $ map makeModel novitaModels
  where
    makeModel mid = Model (ModelId mid) "model" (Timestamp 0) "novita"

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
  401 -> Failure $ AuthError "Invalid Novita API key"
  403 -> Failure $ AuthError "Novita API key lacks permissions"
  429 -> Retry $ RateLimitError "Novita rate limit (should not happen - no limits)"
  408 -> Retry $ TimeoutError "Novita request timeout"
  500 -> Retry $ InternalError $ "Novita 500: " <> bodyText
  502 -> Retry $ ProviderUnavailable "Novita 502 Bad Gateway"
  503 -> Retry $ ProviderUnavailable "Novita 503 Service Unavailable"
  504 -> Retry $ TimeoutError "Novita 504 Gateway Timeout"
  _ -> Failure $ InvalidRequestError $ "Novita " <> T.pack (show status) <> ": " <> bodyText
  where
    bodyText = T.take 500 $ T.pack $ show body
