-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                     // straylight-llm // provider/baseten
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Case fell into the prison of his own flesh."
--
--                                                              — Neuromancer
--
-- Baseten provider backend. Tertiary provider in the fallback chain.
-- OpenAI-compatible API at https://inference.baseten.co/v1
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.Baseten
  ( -- * Provider
    makeBasetenProvider,
  )
where

import Config (ProviderConfig (pcApiKey, pcBaseUrl, pcEnabled))
import Control.Exception (try)
import Data.Aeson (eitherDecode, encode)
import Data.ByteString ()
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
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
    ProviderName (Baseten),
    ProviderResult (..),
    RequestContext (..),
    StreamCallback,
  )
import Types
  ( ChatRequest (..),
    ChatResponse,
    EmbeddingRequest (..),
    EmbeddingResponse,
    ModelId (..),
    ModelList,
  )

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a Baseten provider
makeBasetenProvider :: IORef ProviderConfig -> Provider
makeBasetenProvider configRef =
  Provider
    { providerName = Baseten,
      providerEnabled = isEnabled configRef,
      providerChat = chat configRef,
      providerChatStream = chatStream configRef,
      providerEmbeddings = embeddings configRef,
      providerModels = models configRef,
      providerSupportsModel = supportsModel
    }

-- | Check if Baseten is configured
isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "baseten.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing

-- | Check if model is supported
-- Baseten hosts custom deployments, model support varies by account
supportsModel :: Text -> Bool
supportsModel modelId =
  -- Baseten commonly hosts these model families
  any
    (`T.isPrefixOf` modelId)
    [ "llama-",
      "mistral-",
      "mixtral-",
      "qwen-",
      "deepseek-"
    ]

-- | Non-streaming chat completion
chat :: IORef ProviderConfig -> RequestContext -> ChatRequest -> GatewayM Full (ProviderResult ChatResponse)
chat configRef ctx req = G.do
  recordProvider "baseten"
  recordModel (unModelId $ crModel req)
  config <- liftIO' $ readIORef configRef
  chatWithConfig config ctx req

-- | Chat helper after config loaded
chatWithConfig :: ProviderConfig -> RequestContext -> ChatRequest -> GatewayM Full (ProviderResult ChatResponse)
chatWithConfig config ctx req =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Baseten API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "baseten" "api-key"
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
  recordProvider "baseten"
  recordModel (unModelId $ crModel req)
  config <- liftIO' $ readIORef configRef
  chatStreamWithConfig config ctx req callback

-- | Streaming helper after config loaded
chatStreamWithConfig :: ProviderConfig -> RequestContext -> ChatRequest -> StreamCallback -> GatewayM Full (ProviderResult ())
chatStreamWithConfig config ctx req callback =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Baseten API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "baseten" "api-key"
      let url = T.unpack (pcBaseUrl config) <> "/chat/completions"
          streamReq = req {crStream = Just True}
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- withLatency $ makeStreamingRequest (rcManager ctx) url apiKey (encode streamReq) callback
      liftIO' $ pure $ case result of
        Left err -> classifyError err
        Right () -> Success ()

-- | Generate embeddings
embeddings :: IORef ProviderConfig -> RequestContext -> EmbeddingRequest -> GatewayM Full (ProviderResult EmbeddingResponse)
embeddings configRef ctx req = G.do
  recordProvider "baseten"
  recordModel (unModelId $ embModel req)
  config <- liftIO' $ readIORef configRef
  embeddingsWithConfig config ctx req

-- | Embeddings helper after config loaded
embeddingsWithConfig :: ProviderConfig -> RequestContext -> EmbeddingRequest -> GatewayM Full (ProviderResult EmbeddingResponse)
embeddingsWithConfig config ctx req =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Baseten API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "baseten" "api-key"
      let url = T.unpack (pcBaseUrl config) <> "/embeddings"
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- withLatency $ makeRequest (rcManager ctx) url apiKey (encode req)
      liftIO' $ pure $ case result of
        Left err -> classifyError err
        Right body -> case eitherDecode body of
          Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
          Right resp -> Success resp

-- | List available models
-- n.b. Baseten models are account-specific deployments
models :: IORef ProviderConfig -> RequestContext -> GatewayM Full (ProviderResult ModelList)
models configRef ctx = G.do
  recordProvider "baseten"
  recordConfigAccess "baseten.models"
  config <- liftIO' $ readIORef configRef
  modelsWithConfig config ctx

-- | Models helper after config loaded
modelsWithConfig :: ProviderConfig -> RequestContext -> GatewayM Full (ProviderResult ModelList)
modelsWithConfig config ctx =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Baseten API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "baseten" "api-key"
      let url = T.unpack (pcBaseUrl config) <> "/models"
      recordHttpAccess (T.pack url) "GET" Nothing
      result <- withLatency $ makeGetRequest (rcManager ctx) url apiKey
      liftIO' $ pure $ case result of
        Left err -> classifyError err
        Right body -> case eitherDecode body of
          Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
          Right resp -> Success resp

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
                ("Authorization", "Api-Key " <> encodeUtf8 apiKey)
              ],
            HC.requestBody = HC.RequestBodyLBS body
          }

  result <- try @HttpException $ HC.httpLbs req manager
  case result of
    Left e -> pure $ Left (0, T.pack $ show e)
    Right resp -> do
      let status = HT.statusCode $ HC.responseStatus resp
      if status >= 200 && status < 300
        then pure $ Right $ HC.responseBody resp
        else pure $ Left (status, decodeBody $ HC.responseBody resp)

-- | Make a GET request
makeGetRequest :: HC.Manager -> String -> Text -> IO (Either (Int, Text) LBS.ByteString)
makeGetRequest manager url apiKey = do
  initReq <- HC.parseRequest url
  let req =
        initReq
          { HC.method = "GET",
            HC.requestHeaders =
              [ ("Authorization", "Api-Key " <> encodeUtf8 apiKey)
              ]
          }

  result <- try @HttpException $ HC.httpLbs req manager
  case result of
    Left e -> pure $ Left (0, T.pack $ show e)
    Right resp -> do
      let status = HT.statusCode $ HC.responseStatus resp
      if status >= 200 && status < 300
        then pure $ Right $ HC.responseBody resp
        else pure $ Left (status, decodeBody $ HC.responseBody resp)

-- | Make a streaming POST request
makeStreamingRequest :: HC.Manager -> String -> Text -> LBS.ByteString -> StreamCallback -> IO (Either (Int, Text) ())
makeStreamingRequest manager url apiKey body callback = do
  initReq <- HC.parseRequest url
  let req =
        initReq
          { HC.method = "POST",
            HC.requestHeaders =
              [ ("Content-Type", "application/json"),
                ("Authorization", "Api-Key " <> encodeUtf8 apiKey)
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
        body' <- HC.brConsume $ HC.responseBody resp
        pure $ Left (status, decodeBody $ LBS.fromChunks body')

  case result of
    Left e -> pure $ Left (0, T.pack $ show e)
    Right r -> pure r

-- | Stream response body chunks
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

-- | Decode response body to text
decodeBody :: LBS.ByteString -> Text
decodeBody = T.pack . show . LBS.toStrict

-- | Classify HTTP error into ProviderError
classifyError :: (Int, Text) -> ProviderResult a
classifyError (status, msg)
  | status == 401 = Failure $ AuthError msg
  | status == 429 = Retry $ RateLimitError msg
  | status == 402 = Failure $ QuotaExceededError msg -- Credits exhausted is terminal, not transient
  | status == 404 = Retry $ ModelNotFoundError msg -- Model not found should try next provider
  | status >= 500 = Retry $ ProviderUnavailable msg
  | status >= 400 = Failure $ InvalidRequestError msg
  | status == 0 = Retry $ TimeoutError msg
  | otherwise = Failure $ UnknownError msg
