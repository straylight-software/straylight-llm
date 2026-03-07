-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                     // straylight-llm // provider/sambanova
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd operated on an almost permanent adrenaline high, a byproduct of
--      youth and proficiency, jacked into a custom cyberspace deck."
--
--                                                              — Neuromancer
--
-- SambaNova provider. Chris Ré's company with custom RDU (Reconfigurable
-- Dataflow Unit) hardware. MASSIVE throughput, optimized for MoE models.
--
-- API: https://api.sambanova.ai/v1
-- Docs: https://docs.sambanova.ai
--
-- Key advantages:
--   • RDU hardware - purpose-built for LLM inference
--   • Exceptional throughput (1000+ tokens/sec)
--   • Optimized for MoE (Mixture of Experts) models
--   • DeepSeek V3/R1 at incredible speeds
--   • OpenAI-compatible API
--   • Cheapest $/token for high-quality inference
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.SambaNova
  ( -- * Provider
    makeSambaNovaProvider,
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
    ProviderName (SambaNova),
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

-- | Default SambaNova API base URL
defaultBaseUrl :: Text
defaultBaseUrl = "https://api.sambanova.ai/v1"

-- | Models supported by SambaNova - FOCUS ON MoE FOR COST EFFICIENCY
-- These are the cheapest, fastest options on their RDU hardware
sambanovaModels :: [Text]
sambanovaModels =
  [ -- DeepSeek MoE (PRIORITY - cheapest + fastest)
    "DeepSeek-R1",
    "DeepSeek-R1-Distill-Llama-70B",
    "DeepSeek-V3-0324",
    "DeepSeek-V3",
    -- Qwen MoE
    "QwQ-32B",
    "Qwen2.5-72B-Instruct",
    "Qwen2.5-Coder-32B-Instruct",
    -- Llama (for compatibility)
    "Meta-Llama-3.3-70B-Instruct",
    "Meta-Llama-3.1-405B-Instruct",
    "Meta-Llama-3.1-70B-Instruct",
    "Meta-Llama-3.1-8B-Instruct"
  ]

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | Create SambaNova provider - optimized for MoE throughput
makeSambaNovaProvider :: IORef ProviderConfig -> Provider
makeSambaNovaProvider configRef =
  Provider
    { providerName = SambaNova,
      providerEnabled = isEnabled configRef,
      providerChat = chatCompletion configRef,
      providerChatStream = chatCompletionStream configRef,
      providerEmbeddings = embeddings configRef,
      providerModels = listModels configRef,
      providerSupportsModel = supportsModel
    }

-- | Check if SambaNova is configured and enabled
isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "sambanova.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing

-- | Check if model is supported - prioritize MoE models
supportsModel :: Text -> Bool
supportsModel modelId =
  modelId `elem` sambanovaModels
    || "DeepSeek" `T.isInfixOf` modelId
    || "deepseek" `T.isInfixOf` modelId
    || "Qwen" `T.isInfixOf` modelId
    || "qwen" `T.isInfixOf` modelId
    || "QwQ" `T.isInfixOf` modelId
    || "Llama" `T.isInfixOf` modelId

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
  recordAuthUsage "sambanova" "api-key"
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

-- | Streaming chat completion - SambaNova streams FAST on RDU
chatCompletionStream ::
  IORef ProviderConfig ->
  RequestContext ->
  ChatRequest ->
  StreamCallback ->
  GatewayM Full (ProviderResult ())
chatCompletionStream configRef ctx req callback = G.do
  recordAuthUsage "sambanova" "api-key"
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

-- | Embeddings - SambaNova supports embeddings on RDU
embeddings ::
  IORef ProviderConfig ->
  RequestContext ->
  EmbeddingRequest ->
  GatewayM Full (ProviderResult EmbeddingResponse)
embeddings configRef ctx req = G.do
  recordAuthUsage "sambanova" "api-key"
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

-- | List available models - prioritize MoE for cost efficiency
listModels ::
  IORef ProviderConfig ->
  RequestContext ->
  GatewayM Full (ProviderResult ModelList)
listModels configRef ctx = G.do
  recordAuthUsage "sambanova" "api-key"
  config <- liftIO' $ readIORef configRef

  let baseUrl = if T.null (pcBaseUrl config) then defaultBaseUrl else pcBaseUrl config
      url = T.unpack baseUrl <> "/models"
      apiKey = maybe "" id (pcApiKey config)

  recordHttpAccess (T.pack url) "GET" Nothing

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
              -- Fallback to hardcoded models
              Success $ ModelList "list" $ map makeModel sambanovaModels
            Right r -> Success r
        s -> handleErrorStatus s body
  where
    makeModel mid = Model (ModelId mid) "model" (Timestamp 0) "sambanova"

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
  401 -> Failure $ AuthError "Invalid SambaNova API key"
  403 -> Failure $ AuthError "SambaNova API key lacks permissions"
  429 -> Retry $ RateLimitError "SambaNova rate limit"
  408 -> Retry $ TimeoutError "SambaNova request timeout"
  500 -> Retry $ InternalError $ "SambaNova 500: " <> bodyText
  502 -> Retry $ ProviderUnavailable "SambaNova 502 Bad Gateway"
  503 -> Retry $ ProviderUnavailable "SambaNova 503 Service Unavailable"
  504 -> Retry $ TimeoutError "SambaNova 504 Gateway Timeout"
  _ -> Failure $ InvalidRequestError $ "SambaNova " <> T.pack (show status) <> ": " <> bodyText
  where
    bodyText = T.take 500 $ T.pack $ show body
