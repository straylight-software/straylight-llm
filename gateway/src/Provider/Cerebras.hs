-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                      // straylight-llm // provider/cerebras
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Wintermute was hive mind, decision maker, effecting change in the
--      world outside."
--
--                                                              — Neuromancer
--
-- Cerebras provider. Wafer-scale engine (WSE), enterprise throughput.
-- Massive parallelism, designed for large batch inference.
-- OpenAI-compatible API.
--
-- API: https://api.cerebras.ai/v1
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.Cerebras
  ( makeCerebrasProvider,
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
    ProviderName (Cerebras),
    ProviderResult (Failure, Retry, Success),
    RequestContext (rcManager, rcRequestId),
    StreamCallback,
  )
import Types (ChatRequest, ChatResponse, EmbeddingRequest, EmbeddingResponse, Model (Model), ModelId (ModelId), ModelList (ModelList), Timestamp (Timestamp))

defaultBaseUrl :: Text
defaultBaseUrl = "https://api.cerebras.ai/v1"

-- Cerebras optimized models on WSE
cerebrasModels :: [Text]
cerebrasModels =
  [ "llama3.1-8b",
    "llama3.1-70b",
    "llama-3.3-70b"
  ]

makeCerebrasProvider :: IORef ProviderConfig -> Provider
makeCerebrasProvider configRef =
  Provider
    { providerName = Cerebras,
      providerEnabled = isEnabled configRef,
      providerChat = chatCompletion configRef,
      providerChatStream = chatCompletionStream configRef,
      providerEmbeddings = embeddings configRef,
      providerModels = listModels configRef,
      providerSupportsModel = supportsModel
    }

isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "cerebras.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing

supportsModel :: Text -> Bool
supportsModel modelId = modelId `elem` cerebrasModels || "llama" `T.isInfixOf` T.toLower modelId

chatCompletion :: IORef ProviderConfig -> RequestContext -> ChatRequest -> GatewayM Full (ProviderResult ChatResponse)
chatCompletion configRef ctx req = G.do
  recordAuthUsage "cerebras" "api-key"
  config <- liftIO' $ readIORef configRef
  let baseUrl = if T.null (pcBaseUrl config) then defaultBaseUrl else pcBaseUrl config
      url = T.unpack baseUrl <> "/chat/completions"
      apiKey = maybe "" id (pcApiKey config)
  recordHttpAccess (T.pack url) "POST" Nothing
  result <- liftIO' $ do
    initReq <- HC.parseRequest url
    let httpReq = initReq {HC.method = "POST", HC.requestHeaders = [("Authorization", "Bearer " <> encodeUtf8 apiKey), ("Content-Type", "application/json"), ("X-Request-ID", encodeUtf8 $ rcRequestId ctx)], HC.requestBody = HC.RequestBodyLBS (encode req)}
    tryResult <- try @HttpException $ HC.httpLbs httpReq (rcManager ctx)
    pure $ case tryResult of Left e -> Left $ ProviderUnavailable $ T.pack $ show e; Right resp -> Right resp
  case result of
    Left err -> liftIO' $ pure $ Retry err
    Right resp -> liftIO' $ pure $ handleResponse (HT.statusCode $ HC.responseStatus resp) (HC.responseBody resp)

chatCompletionStream :: IORef ProviderConfig -> RequestContext -> ChatRequest -> StreamCallback -> GatewayM Full (ProviderResult ())
chatCompletionStream configRef ctx req callback = G.do
  recordAuthUsage "cerebras" "api-key"
  config <- liftIO' $ readIORef configRef
  let baseUrl = if T.null (pcBaseUrl config) then defaultBaseUrl else pcBaseUrl config
      url = T.unpack baseUrl <> "/chat/completions"
      apiKey = maybe "" id (pcApiKey config)
  recordHttpAccess (T.pack url) "POST" Nothing
  result <- liftIO' $ do
    initReq <- HC.parseRequest url
    let httpReq = initReq {HC.method = "POST", HC.requestHeaders = [("Authorization", "Bearer " <> encodeUtf8 apiKey), ("Content-Type", "application/json"), ("Accept", "text/event-stream"), ("X-Request-ID", encodeUtf8 $ rcRequestId ctx)], HC.requestBody = HC.RequestBodyLBS (encode req)}
    tryResult <- try @HttpException $ HC.withResponse httpReq (rcManager ctx) $ \resp -> do
      let status = HT.statusCode $ HC.responseStatus resp
      if status >= 200 && status < 300 then do streamBody (HC.responseBody resp) callback; pure Nothing else do body <- HC.brConsume (HC.responseBody resp); pure $ Just $ handleErrorStatus status (LBS.fromChunks body)
    pure $ case tryResult of Left e -> Retry $ ProviderUnavailable $ T.pack $ show e; Right Nothing -> Success (); Right (Just provResult) -> provResult
  liftIO' $ pure result

streamBody :: HC.BodyReader -> StreamCallback -> IO ()
streamBody bodyReader callback = go where go = do chunk <- HC.brRead bodyReader; if chunk == "" then pure () else do callback chunk; go

embeddings :: IORef ProviderConfig -> RequestContext -> EmbeddingRequest -> GatewayM Full (ProviderResult EmbeddingResponse)
embeddings _ _ _ = G.do liftIO' $ pure $ Failure $ InvalidRequestError "Cerebras embeddings not implemented"

listModels :: IORef ProviderConfig -> RequestContext -> GatewayM Full (ProviderResult ModelList)
listModels _ _ = G.do liftIO' $ pure $ Success $ ModelList "list" $ map (\mid -> Model (ModelId mid) "model" (Timestamp 0) "cerebras") cerebrasModels

handleResponse :: Int -> LBS.ByteString -> ProviderResult ChatResponse
handleResponse status body | status >= 200 && status < 300 = case eitherDecode body of Left e -> Failure $ InternalError $ "Parse error: " <> T.pack e; Right r -> Success r | otherwise = handleErrorStatus status body

handleErrorStatus :: Int -> LBS.ByteString -> ProviderResult a
handleErrorStatus status body = case status of
  401 -> Failure $ AuthError "Invalid Cerebras API key"
  429 -> Retry $ RateLimitError "Cerebras rate limit"
  500 -> Retry $ InternalError $ "Cerebras 500: " <> bodyText
  502 -> Retry $ ProviderUnavailable "Cerebras 502"
  503 -> Retry $ ProviderUnavailable "Cerebras 503"
  504 -> Retry $ TimeoutError "Cerebras 504"
  _ -> Failure $ InvalidRequestError $ "Cerebras " <> T.pack (show status) <> ": " <> bodyText
  where
    bodyText = T.take 500 $ T.pack $ show body
