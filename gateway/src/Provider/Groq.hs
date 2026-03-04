-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                          // straylight-llm // provider/groq
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "It was a vast thing, a thing of crystalline grace."
--
--                                                              — Neuromancer
--
-- Groq provider. LPU (Language Processing Unit) hardware.
-- Insane speed (~500 tokens/sec), limited model selection.
-- OpenAI-compatible API.
--
-- API: https://api.groq.com/openai/v1
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.Groq
  ( makeGroqProvider,
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
import Effects.Graded (Full, GatewayM, liftIO', recordAuthUsage, recordConfigAccess, recordHttpAccess, recordModel, recordProvider, withLatency)
import Network.HTTP.Client (HttpException)
import Network.HTTP.Client qualified as HC
import Network.HTTP.Types qualified as HT
import Provider.Types
  ( Provider (Provider, providerChat, providerChatStream, providerEmbeddings, providerEnabled, providerModels, providerName, providerSupportsModel),
    ProviderError (AuthError, InternalError, InvalidRequestError, ProviderUnavailable, RateLimitError, TimeoutError, UnknownError),
    ProviderName (Groq),
    ProviderResult (Failure, Retry, Success),
    RequestContext (rcManager),
    StreamCallback,
  )
import Types (ChatRequest (crModel), ChatResponse, EmbeddingRequest, EmbeddingResponse, Model (Model), ModelId (ModelId, unModelId), ModelList (ModelList), Timestamp (Timestamp))

-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // models
-- ════════════════════════════════════════════════════════════════════════════

-- | Groq focuses on speed - limited model selection but blazing fast
groqModels :: [Text]
groqModels =
  [ "llama-3.3-70b-versatile",
    "llama-3.1-8b-instant",
    "mixtral-8x7b-32768",
    "gemma2-9b-it",
    "deepseek-r1-distill-llama-70b"
  ]

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

makeGroqProvider :: IORef ProviderConfig -> Provider
makeGroqProvider configRef =
  Provider
    { providerName = Groq,
      providerEnabled = isEnabled configRef,
      providerChat = chat configRef,
      providerChatStream = chatStream configRef,
      providerEmbeddings = embeddings configRef,
      providerModels = models configRef,
      providerSupportsModel = supportsModel
    }

-- | Check if Groq is configured
isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "groq.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing

-- | Check if model is supported
supportsModel :: Text -> Bool
supportsModel modelId =
  modelId `elem` groqModels
    || "llama" `T.isInfixOf` T.toLower modelId
    || "mixtral" `T.isInfixOf` T.toLower modelId

-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // chat
-- ════════════════════════════════════════════════════════════════════════════

-- | Non-streaming chat completion
chat :: IORef ProviderConfig -> RequestContext -> ChatRequest -> GatewayM Full (ProviderResult ChatResponse)
chat configRef ctx req = G.do
  recordProvider "groq"
  recordModel (unModelId $ crModel req)
  config <- liftIO' $ readIORef configRef
  chatWithConfig config ctx req

-- | Chat implementation after config is loaded
chatWithConfig :: ProviderConfig -> RequestContext -> ChatRequest -> GatewayM Full (ProviderResult ChatResponse)
chatWithConfig config ctx req =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Groq API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "groq" "api-key"
      let url = T.unpack (pcBaseUrl config) <> "/chat/completions"
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- withLatency $ makeRequest (rcManager ctx) url apiKey (encode req)
      liftIO' $ pure $ case result of
        Left err -> classifyError err
        Right body -> case eitherDecode body of
          Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
          Right resp -> Success resp

-- | Streaming chat completion
chatStream :: IORef ProviderConfig -> RequestContext -> ChatRequest -> StreamCallback -> GatewayM Full (ProviderResult ())
chatStream configRef ctx req callback = G.do
  recordProvider "groq"
  recordModel (unModelId $ crModel req)
  config <- liftIO' $ readIORef configRef
  chatStreamWithConfig config ctx req callback

-- | Streaming implementation after config is loaded
chatStreamWithConfig :: ProviderConfig -> RequestContext -> ChatRequest -> StreamCallback -> GatewayM Full (ProviderResult ())
chatStreamWithConfig config ctx req callback =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Groq API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "groq" "api-key"
      let url = T.unpack (pcBaseUrl config) <> "/chat/completions"
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- liftIO' $ makeStreamRequest (rcManager ctx) url apiKey (encode req) callback
      liftIO' $ pure result

-- ════════════════════════════════════════════════════════════════════════════
--                                                              // embeddings
-- ════════════════════════════════════════════════════════════════════════════

-- | Groq does not support embeddings
embeddings :: IORef ProviderConfig -> RequestContext -> EmbeddingRequest -> GatewayM Full (ProviderResult EmbeddingResponse)
embeddings _configRef _ctx _req = G.do
  liftIO' $ pure $ Failure $ InvalidRequestError "Groq does not support embeddings"

-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // models
-- ════════════════════════════════════════════════════════════════════════════

-- | List available models (hardcoded - Groq has limited selection)
models :: IORef ProviderConfig -> RequestContext -> GatewayM Full (ProviderResult ModelList)
models _configRef _ctx = G.do
  liftIO' $ pure $ Success $ ModelList "list" $ map toModel groqModels
  where
    toModel mid = Model (ModelId mid) "model" (Timestamp 0) "groq"

-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // http
-- ════════════════════════════════════════════════════════════════════════════

-- | Make a POST request
makeRequest :: HC.Manager -> String -> Text -> LBS.ByteString -> IO (Either (Int, Text) LBS.ByteString)
makeRequest manager url apiKey body = do
  initReq <- HC.parseRequest url
  let req =
        initReq
          { HC.method = "POST",
            HC.requestHeaders =
              [ ("Content-Type", "application/json"),
                ("Authorization", "Bearer " <> encodeUtf8 apiKey)
              ],
            HC.requestBody = HC.RequestBodyLBS body
          }
  result <- try @HttpException $ HC.httpLbs req manager
  case result of
    Left e -> pure $ Left (0, T.pack $ show e)
    Right resp ->
      let status = HT.statusCode $ HC.responseStatus resp
       in if status >= 200 && status < 300
            then pure $ Right $ HC.responseBody resp
            else pure $ Left (status, "HTTP " <> T.pack (show status))

-- | Make a streaming POST request
makeStreamRequest :: HC.Manager -> String -> Text -> LBS.ByteString -> StreamCallback -> IO (ProviderResult ())
makeStreamRequest manager url apiKey body callback = do
  initReq <- HC.parseRequest url
  let req =
        initReq
          { HC.method = "POST",
            HC.requestHeaders =
              [ ("Content-Type", "application/json"),
                ("Authorization", "Bearer " <> encodeUtf8 apiKey),
                ("Accept", "text/event-stream")
              ],
            HC.requestBody = HC.RequestBodyLBS body
          }
  result <- try @HttpException $ HC.withResponse req manager $ \resp -> do
    let status = HT.statusCode $ HC.responseStatus resp
    if status >= 200 && status < 300
      then do
        streamBody (HC.responseBody resp) callback
        pure $ Right ()
      else do
        respBody <- HC.brConsume (HC.responseBody resp)
        pure $ Left (status, LBS.fromChunks respBody)
  case result of
    Left e -> pure $ Retry $ ProviderUnavailable $ T.pack $ show e
    Right (Left (status, _)) -> pure $ classifyError (status, "Stream error")
    Right (Right ()) -> pure $ Success ()

-- | Stream response body chunks
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
--                                                                  // errors
-- ════════════════════════════════════════════════════════════════════════════

-- | Classify HTTP errors
classifyError :: (Int, Text) -> ProviderResult a
classifyError (status, _msg) = case status of
  0 -> Retry $ ProviderUnavailable "Connection failed"
  401 -> Failure $ AuthError "Invalid Groq API key"
  403 -> Failure $ AuthError "Groq access denied"
  429 -> Retry $ RateLimitError "Groq rate limited"
  500 -> Retry $ InternalError "Groq internal error"
  502 -> Retry $ ProviderUnavailable "Groq bad gateway"
  503 -> Retry $ ProviderUnavailable "Groq unavailable"
  504 -> Retry $ TimeoutError "Groq gateway timeout"
  _ -> Failure $ InvalidRequestError $ "Groq error " <> T.pack (show status)
