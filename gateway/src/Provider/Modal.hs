-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                         // straylight-llm // provider/modal
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Cyberspace. A consensual hallucination experienced daily by billions."
--
--                                                              — Neuromancer
--
-- Modal provider. Serverless GPU, pay-per-second, burst capacity.
-- Requires user-deployed Modal app with OpenAI-compatible endpoint.
--
-- Modal is different from other providers:
--   • No fixed API endpoint - user deploys their own Modal app
--   • User configures pcBaseUrl to their deployed endpoint
--   • Endpoint should be OpenAI-compatible (user's responsibility)
--   • Burst capacity for variable workloads
--
-- Setup:
--   1. Deploy Modal app with OpenAI-compatible /chat/completions endpoint
--   2. Set MODAL_BASE_URL to your deployed endpoint
--   3. Set MODAL_API_KEY if your endpoint requires auth
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.Modal
  ( makeModalProvider,
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
  ( Provider (Provider, providerChat, providerChatStream, providerEmbeddings, providerEnabled, providerModels, providerName, providerSupportsModel),
    ProviderError (AuthError, InternalError, InvalidRequestError, ProviderUnavailable, RateLimitError, TimeoutError),
    ProviderName (Modal),
    ProviderResult (Failure, Retry, Success),
    RequestContext (rcManager, rcRequestId),
    StreamCallback,
  )
import Types (ChatRequest, ChatResponse, EmbeddingRequest, EmbeddingResponse, Model (Model), ModelId (ModelId), ModelList (ModelList), Timestamp (Timestamp))

-- | Create Modal provider
-- Modal requires pcBaseUrl to be configured with the deployed endpoint
makeModalProvider :: IORef ProviderConfig -> Provider
makeModalProvider configRef =
  Provider
    { providerName = Modal,
      providerEnabled = isEnabled configRef,
      providerChat = chatCompletion configRef,
      providerChatStream = chatCompletionStream configRef,
      providerEmbeddings = embeddings configRef,
      providerModels = listModels configRef,
      providerSupportsModel = supportsModel
    }

-- | Modal is enabled only if both API key and base URL are configured
-- Base URL is required because Modal doesn't have a standard endpoint
isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "modal.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing && not (T.null (pcBaseUrl config))

-- | Modal supports any model the user deploys - always return True
-- The user's Modal app determines what models are available
supportsModel :: Text -> Bool
supportsModel _ = True

-- | Non-streaming chat completion
chatCompletion :: IORef ProviderConfig -> RequestContext -> ChatRequest -> GatewayM Full (ProviderResult ChatResponse)
chatCompletion configRef ctx req = G.do
  recordAuthUsage "modal" "api-key"
  config <- liftIO' $ readIORef configRef
  let baseUrl = pcBaseUrl config
  if T.null baseUrl
    then liftIO' $ pure $ Failure $ InvalidRequestError "Modal requires pcBaseUrl - set MODAL_BASE_URL to your deployed endpoint"
    else G.do
      let url = T.unpack baseUrl <> "/chat/completions"
          apiKey = maybe "" id (pcApiKey config)
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- liftIO' $ do
        initReq <- HC.parseRequest url
        let httpReq = initReq
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
        Right resp -> liftIO' $ pure $ handleResponse (HT.statusCode $ HC.responseStatus resp) (HC.responseBody resp)

-- | Streaming chat completion
chatCompletionStream :: IORef ProviderConfig -> RequestContext -> ChatRequest -> StreamCallback -> GatewayM Full (ProviderResult ())
chatCompletionStream configRef ctx req callback = G.do
  recordAuthUsage "modal" "api-key"
  config <- liftIO' $ readIORef configRef
  let baseUrl = pcBaseUrl config
  if T.null baseUrl
    then liftIO' $ pure $ Failure $ InvalidRequestError "Modal requires pcBaseUrl - set MODAL_BASE_URL to your deployed endpoint"
    else G.do
      let url = T.unpack baseUrl <> "/chat/completions"
          apiKey = maybe "" id (pcApiKey config)
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- liftIO' $ do
        initReq <- HC.parseRequest url
        let httpReq = initReq
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

-- | Embeddings - depends on user's Modal deployment
embeddings :: IORef ProviderConfig -> RequestContext -> EmbeddingRequest -> GatewayM Full (ProviderResult EmbeddingResponse)
embeddings configRef ctx req = G.do
  recordAuthUsage "modal" "api-key"
  config <- liftIO' $ readIORef configRef
  let baseUrl = pcBaseUrl config
  if T.null baseUrl
    then liftIO' $ pure $ Failure $ InvalidRequestError "Modal requires pcBaseUrl - set MODAL_BASE_URL to your deployed endpoint"
    else G.do
      let url = T.unpack baseUrl <> "/embeddings"
          apiKey = maybe "" id (pcApiKey config)
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- liftIO' $ do
        initReq <- HC.parseRequest url
        let httpReq = initReq
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

-- | List models - Modal doesn't have a standard models endpoint
-- Return empty list; user knows what models their deployment supports
listModels :: IORef ProviderConfig -> RequestContext -> GatewayM Full (ProviderResult ModelList)
listModels _ _ = G.do
  liftIO' $ pure $ Success $ ModelList "list" [Model (ModelId "modal/custom") "model" (Timestamp 0) "modal"]

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
handleErrorStatus status _ = case status of
  401 -> Failure $ AuthError "Invalid Modal API key or unauthorized"
  403 -> Failure $ AuthError "Modal endpoint access forbidden"
  404 -> Failure $ InvalidRequestError "Modal endpoint not found - check MODAL_BASE_URL"
  429 -> Retry $ RateLimitError "Modal rate limit"
  500 -> Retry $ InternalError "Modal 500 Internal Server Error"
  502 -> Retry $ ProviderUnavailable "Modal 502 Bad Gateway"
  503 -> Retry $ ProviderUnavailable "Modal 503 Service Unavailable"
  504 -> Retry $ TimeoutError "Modal 504 Gateway Timeout"
  _ -> Failure $ InvalidRequestError $ "Modal " <> T.pack (show status)
