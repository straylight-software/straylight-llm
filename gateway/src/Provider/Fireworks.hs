-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                     // straylight-llm // provider/fireworks
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "A year here and he still dreamed of cyberspace."
--
--                                                              — Neuromancer
--
-- Fireworks AI provider. Optimized inference, high throughput.
-- OpenAI-compatible API.
--
-- API: https://api.fireworks.ai/inference/v1
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.Fireworks
  ( makeFireworksProvider,
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
    ProviderName (Fireworks),
    ProviderResult (Failure, Retry, Success),
    RequestContext (rcManager, rcRequestId),
    StreamCallback,
  )
import Types (ChatRequest, ChatResponse, EmbeddingRequest, EmbeddingResponse, Model (Model), ModelId (ModelId), ModelList (ModelList))

defaultBaseUrl :: Text
defaultBaseUrl = "https://api.fireworks.ai/inference/v1"

fireworksModels :: [Text]
fireworksModels =
  [ "accounts/fireworks/models/deepseek-v3",
    "accounts/fireworks/models/deepseek-r1",
    "accounts/fireworks/models/qwen2p5-72b-instruct",
    "accounts/fireworks/models/llama-v3p3-70b-instruct",
    "accounts/fireworks/models/mixtral-8x22b-instruct"
  ]

makeFireworksProvider :: IORef ProviderConfig -> Provider
makeFireworksProvider configRef =
  Provider
    { providerName = Fireworks,
      providerEnabled = isEnabled configRef,
      providerChat = chatCompletion configRef,
      providerChatStream = chatCompletionStream configRef,
      providerEmbeddings = embeddings configRef,
      providerModels = listModels configRef,
      providerSupportsModel = supportsModel
    }

isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "fireworks.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing

supportsModel :: Text -> Bool
supportsModel modelId = modelId `elem` fireworksModels || "deepseek" `T.isInfixOf` T.toLower modelId

chatCompletion :: IORef ProviderConfig -> RequestContext -> ChatRequest -> GatewayM Full (ProviderResult ChatResponse)
chatCompletion configRef ctx req = G.do
  recordAuthUsage "fireworks" Nothing
  config <- liftIO' $ readIORef configRef
  let baseUrl = maybe defaultBaseUrl id (pcBaseUrl config)
      url = T.unpack baseUrl <> "/chat/completions"
      apiKey = maybe "" id (pcApiKey config)
  recordHttpAccess url "POST"
  result <- liftIO' $ do
    initReq <- HC.parseRequest url
    let httpReq = initReq {HC.method = "POST", HC.requestHeaders = [("Authorization", "Bearer " <> encodeUtf8 apiKey), ("Content-Type", "application/json")], HC.requestBody = HC.RequestBodyLBS (encode req)}
    tryResult <- try @HttpException $ HC.httpLbs httpReq (rcManager ctx)
    pure $ case tryResult of Left e -> Left $ ProviderUnavailable $ T.pack $ show e; Right resp -> Right resp
  case result of
    Left err -> liftIO' $ pure $ Retry err
    Right resp -> liftIO' $ pure $ handleResponse (HT.statusCode $ HC.responseStatus resp) (HC.responseBody resp)

chatCompletionStream :: IORef ProviderConfig -> RequestContext -> ChatRequest -> StreamCallback -> GatewayM Full (ProviderResult ())
chatCompletionStream configRef ctx req callback = G.do
  recordAuthUsage "fireworks" Nothing
  config <- liftIO' $ readIORef configRef
  let baseUrl = maybe defaultBaseUrl id (pcBaseUrl config)
      url = T.unpack baseUrl <> "/chat/completions"
      apiKey = maybe "" id (pcApiKey config)
  recordHttpAccess url "POST"
  result <- liftIO' $ do
    initReq <- HC.parseRequest url
    let httpReq = initReq {HC.method = "POST", HC.requestHeaders = [("Authorization", "Bearer " <> encodeUtf8 apiKey), ("Content-Type", "application/json"), ("Accept", "text/event-stream")], HC.requestBody = HC.RequestBodyLBS (encode req)}
    tryResult <- try @HttpException $ HC.withResponse httpReq (rcManager ctx) $ \resp -> do
      let status = HT.statusCode $ HC.responseStatus resp
      if status >= 200 && status < 300 then do streamBody (HC.responseBody resp) callback; pure $ Right () else do body <- HC.brConsume (HC.responseBody resp); pure $ Left $ handleErrorStatus status (LBS.fromChunks body)
    pure $ case tryResult of Left e -> Left $ ProviderUnavailable $ T.pack $ show e; Right r -> r
  case result of Left err -> liftIO' $ pure $ Retry err; Right () -> liftIO' $ pure $ Success ()

streamBody :: HC.BodyReader -> StreamCallback -> IO ()
streamBody bodyReader callback = go where go = do chunk <- HC.brRead bodyReader; if chunk == "" then pure () else do callback chunk; go

embeddings :: IORef ProviderConfig -> RequestContext -> EmbeddingRequest -> GatewayM Full (ProviderResult EmbeddingResponse)
embeddings _ _ _ = G.do liftIO' $ pure $ Failure $ InvalidRequestError "Fireworks embeddings not implemented"

listModels :: IORef ProviderConfig -> RequestContext -> GatewayM Full (ProviderResult ModelList)
listModels _ _ = G.do liftIO' $ pure $ Success $ ModelList "list" $ map (\mid -> Model {Types.modelId = ModelId mid, Types.modelObject = "model", Types.modelCreated = 0, Types.modelOwnedBy = "fireworks"}) fireworksModels

handleResponse :: Int -> LBS.ByteString -> ProviderResult ChatResponse
handleResponse status body | status >= 200 && status < 300 = case eitherDecode body of Left e -> Failure $ InternalError $ "Parse error: " <> T.pack e; Right r -> Success r | otherwise = handleErrorStatus status body

handleErrorStatus :: Int -> LBS.ByteString -> ProviderResult a
handleErrorStatus status body = case status of 401 -> Failure $ AuthError "Invalid Fireworks API key"; 429 -> Retry $ RateLimitError "Fireworks rate limit"; 500 -> Retry $ InternalError $ "Fireworks 500"; 502 -> Retry $ ProviderUnavailable "Fireworks 502"; 503 -> Retry $ ProviderUnavailable "Fireworks 503"; 504 -> Retry $ TimeoutError "Fireworks 504"; _ -> Failure $ InvalidRequestError $ "Fireworks " <> T.pack (show status)
