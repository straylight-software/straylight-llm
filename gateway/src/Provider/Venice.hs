-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                      // straylight-llm // provider/venice
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "They were in the back of the Mercedes, sun on the wet asphalt, on
--      the chrome, and he was seeing it all through the blue glass of
--      Armitage's glasses."
--
--                                                              — Neuromancer
--
-- Venice AI provider backend. Primary provider in the fallback chain.
-- OpenAI-compatible API at https://api.venice.ai/api/v1
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.Venice
  ( -- * Provider
    makeVeniceProvider,
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
import Effects.Grade (Full)
import Effects.Graded
  ( GatewayM,
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
    ProviderError
      ( AuthError,
        InvalidRequestError,
        ModelNotFoundError,
        ProviderUnavailable,
        QuotaExceededError,
        RateLimitError,
        TimeoutError,
        UnknownError
      ),
    ProviderName (Venice),
    ProviderResult (Failure, Retry, Success),
    RequestContext (rcManager),
    StreamCallback,
  )
import Types
  ( ChatRequest (crModel, crStream),
    ChatResponse,
    EmbeddingRequest (embModel),
    EmbeddingResponse,
    Model (Model),
    ModelId (ModelId, unModelId),
    ModelList (ModelList),
    Timestamp (Timestamp),
  )

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | Supported Venice models (subset - Venice supports many models)
veniceModels :: [Text]
veniceModels =
  [ "llama-3.3-70b",
    "llama-3.1-405b",
    "deepseek-r1",
    "deepseek-r1-671b",
    "qwen-2.5-coder",
    "dolphin-2.9.2-qwen2-72b"
  ]

-- | Create a Venice AI provider
makeVeniceProvider :: IORef ProviderConfig -> Provider
makeVeniceProvider configRef =
  Provider
    { providerName = Venice,
      providerEnabled = isEnabled configRef,
      providerChat = chat configRef,
      providerChatStream = chatStream configRef,
      providerEmbeddings = embeddings configRef,
      providerModels = models configRef,
      providerSupportsModel = supportsModel
    }

-- | Check if Venice is configured
isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "venice.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing

-- | Check if model is supported
supportsModel :: Text -> Bool
supportsModel modelId =
  -- Venice supports these model prefixes
  any
    (`T.isPrefixOf` modelId)
    [ "llama-",
      "deepseek-",
      "qwen-",
      "dolphin-",
      "mistral-"
    ]

-- | Non-streaming chat completion
chat :: IORef ProviderConfig -> RequestContext -> ChatRequest -> GatewayM Full (ProviderResult ChatResponse)
chat configRef ctx req = G.do
  recordProvider "venice"
  recordModel (unModelId $ crModel req)
  config <- liftIO' $ readIORef configRef
  chatWithConfig config ctx req

-- | Chat implementation after config is loaded
chatWithConfig :: ProviderConfig -> RequestContext -> ChatRequest -> GatewayM Full (ProviderResult ChatResponse)
chatWithConfig config ctx req =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Venice API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "venice" "api-key"
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
  recordProvider "venice"
  recordModel (unModelId $ crModel req)
  config <- liftIO' $ readIORef configRef
  chatStreamWithConfig config ctx req callback

-- | Streaming chat implementation after config is loaded
chatStreamWithConfig :: ProviderConfig -> RequestContext -> ChatRequest -> StreamCallback -> GatewayM Full (ProviderResult ())
chatStreamWithConfig config ctx req callback =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Venice API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "venice" "api-key"
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
  recordProvider "venice"
  recordModel (unModelId $ embModel req)
  config <- liftIO' $ readIORef configRef
  embeddingsWithConfig config ctx req

-- | Embeddings implementation after config is loaded
embeddingsWithConfig :: ProviderConfig -> RequestContext -> EmbeddingRequest -> GatewayM Full (ProviderResult EmbeddingResponse)
embeddingsWithConfig config ctx req =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Venice API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "venice" "api-key"
      let url = T.unpack (pcBaseUrl config) <> "/embeddings"
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- withLatency $ makeRequest (rcManager ctx) url apiKey (encode req)
      liftIO' $ pure $ case result of
        Left err -> classifyError err
        Right body -> case eitherDecode body of
          Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
          Right resp -> Success resp

-- | List available models
models :: IORef ProviderConfig -> RequestContext -> GatewayM Full (ProviderResult ModelList)
models configRef ctx = G.do
  recordProvider "venice"
  recordConfigAccess "venice.models"
  config <- liftIO' $ readIORef configRef
  modelsWithConfig config ctx

-- | Models implementation after config is loaded
modelsWithConfig :: ProviderConfig -> RequestContext -> GatewayM Full (ProviderResult ModelList)
modelsWithConfig config ctx =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "Venice API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "venice" "api-key"
      let url = T.unpack (pcBaseUrl config) <> "/models"
      recordHttpAccess (T.pack url) "GET" Nothing
      result <- withLatency $ makeGetRequest (rcManager ctx) url apiKey
      liftIO' $ pure $ case result of
        Left err -> classifyError err
        Right body -> case eitherDecode body of
          Left _ ->
            -- If models endpoint fails, return hardcoded list
            Success $ ModelList "list" $ map toModel veniceModels
          Right resp -> Success resp
  where
    toModel mid = Model (ModelId mid) "model" (Timestamp 0) "venice"

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
              [ ("Authorization", "Bearer " <> encodeUtf8 apiKey)
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
                ("Authorization", "Bearer " <> encodeUtf8 apiKey)
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
