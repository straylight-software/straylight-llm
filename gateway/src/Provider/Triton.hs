-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                       // straylight-llm // provider/triton
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd found his destiny waiting for him there in the ranked
--      arcades of the Night City pinball emporiums."
--
--                                                              — Neuromancer
--
-- Local Triton/TensorRT-LLM provider. FIRST in the fallback chain when
-- enabled. Achieves ~50-200ms latency vs 2+ seconds through cloud providers.
--
-- Uses the openai-proxy wrapper that exposes Triton at port 9000 with an
-- OpenAI-compatible API (same request/response format as OpenAI).
--
-- No authentication required for local inference.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.Triton
  ( -- * Provider
    makeTritonProvider,
  )
where

import Config (ProviderConfig (pcBaseUrl, pcEnabled))
import Control.Exception (try)
import Data.Aeson (eitherDecode, encode)
import Data.ByteString ()
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Effects.Graded
  ( GatewayM,
    liftGatewayIO,
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
    ProviderName (Triton),
    ProviderResult (..),
    RequestContext (..),
    StreamCallback,
  )
import Types
  ( ChatRequest (..),
    ChatResponse,
    EmbeddingRequest,
    EmbeddingResponse,
    Model (..),
    ModelId (..),
    ModelList (..),
    Timestamp (..),
  )

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a Triton provider for local TensorRT-LLM inference
makeTritonProvider :: IORef ProviderConfig -> Provider
makeTritonProvider configRef =
  Provider
    { providerName = Triton,
      providerEnabled = isEnabled configRef,
      providerChat = chat configRef,
      providerChatStream = chatStream configRef,
      providerEmbeddings = embeddings configRef,
      providerModels = models configRef,
      providerSupportsModel = supportsModel
    }

-- | Check if Triton is configured and enabled
-- Unlike cloud providers, Triton doesn't require an API key
isEnabled :: IORef ProviderConfig -> GatewayM Bool
isEnabled configRef = do
  recordConfigAccess "triton.enabled"
  config <- liftGatewayIO $ readIORef configRef
  pure $ pcEnabled config

-- | Check if model is supported by Triton
-- Triton typically runs specific models like Llama variants
-- The openai-proxy will return an error if model isn't loaded
supportsModel :: Text -> Bool
supportsModel modelId =
  -- Triton commonly runs these model families via TensorRT-LLM
  any
    (`T.isPrefixOf` modelId)
    [ "llama",
      "meta-llama",
      "codellama",
      "mistral",
      "mixtral",
      "qwen",
      "deepseek",
      "phi"
    ]
    ||
    -- Also accept explicit triton/ prefix
    "triton/" `T.isPrefixOf` modelId
    ||
    -- Or local/ prefix for any local model
    "local/" `T.isPrefixOf` modelId

-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // chat
-- ════════════════════════════════════════════════════════════════════════════

-- | Non-streaming chat completion via Triton
chat :: IORef ProviderConfig -> RequestContext -> ChatRequest -> GatewayM (ProviderResult ChatResponse)
chat configRef ctx req = do
  recordProvider "triton"
  recordModel (unModelId $ crModel req)
  config <- liftGatewayIO $ readIORef configRef
  let url = T.unpack (pcBaseUrl config) <> "/chat/completions"
  recordHttpAccess (T.pack url) "POST" Nothing
  result <- withLatency $ makeRequest (rcManager ctx) url (encode req)
  pure $ case result of
    Left err -> classifyError err
    Right body -> case eitherDecode body of
      Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
      Right resp -> Success resp

-- | Streaming chat completion via Triton
chatStream :: IORef ProviderConfig -> RequestContext -> ChatRequest -> StreamCallback -> GatewayM (ProviderResult ())
chatStream configRef ctx req callback = do
  recordProvider "triton"
  recordModel (unModelId $ crModel req)
  config <- liftGatewayIO $ readIORef configRef
  let url = T.unpack (pcBaseUrl config) <> "/chat/completions"
      streamReq = req {crStream = Just True}
  recordHttpAccess (T.pack url) "POST" Nothing
  result <- withLatency $ makeStreamingRequest (rcManager ctx) url (encode streamReq) callback
  pure $ case result of
    Left err -> classifyError err
    Right () -> Success ()

-- | Generate embeddings via Triton
-- TensorRT-LLM can also serve embedding models
embeddings :: IORef ProviderConfig -> RequestContext -> EmbeddingRequest -> GatewayM (ProviderResult EmbeddingResponse)
embeddings configRef ctx req = do
  recordProvider "triton"
  config <- liftGatewayIO $ readIORef configRef
  let url = T.unpack (pcBaseUrl config) <> "/embeddings"
  recordHttpAccess (T.pack url) "POST" Nothing
  result <- withLatency $ makeRequest (rcManager ctx) url (encode req)
  pure $ case result of
    Left err -> classifyError err
    Right body -> case eitherDecode body of
      Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
      Right resp -> Success resp

-- | List available models from Triton
models :: IORef ProviderConfig -> RequestContext -> GatewayM (ProviderResult ModelList)
models configRef ctx = do
  recordProvider "triton"
  recordConfigAccess "triton.models"
  config <- liftGatewayIO $ readIORef configRef
  let url = T.unpack (pcBaseUrl config) <> "/models"
  recordHttpAccess (T.pack url) "GET" Nothing
  result <- withLatency $ makeGetRequest (rcManager ctx) url
  pure $ case result of
    Left err ->
      -- If Triton models endpoint fails, return synthetic list
      -- based on commonly-loaded models
      case err of
        (404, _) -> Success $ syntheticModelList
        _ -> classifyError err
    Right body -> case eitherDecode body of
      Left _parseErr ->
        -- openai-proxy might not implement /models
        Success syntheticModelList
      Right resp -> Success resp

-- | Synthetic model list for when Triton doesn't expose /models
syntheticModelList :: ModelList
syntheticModelList =
  ModelList
    "list"
    [ Model
        { modelId = ModelId "local/llama",
          modelObject = "model",
          modelCreated = Timestamp 1700000000,
          modelOwnedBy = "triton"
        }
    ]

-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // http
-- ════════════════════════════════════════════════════════════════════════════

-- | Make a POST request to Triton (no auth headers needed)
makeRequest :: HC.Manager -> String -> LBS.ByteString -> IO (Either (Int, Text) LBS.ByteString)
makeRequest manager url body = do
  initReq <- HC.parseRequest url
  let req =
        initReq
          { HC.method = "POST",
            HC.requestHeaders =
              [ ("Content-Type", "application/json")
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

-- | Make a GET request to Triton
makeGetRequest :: HC.Manager -> String -> IO (Either (Int, Text) LBS.ByteString)
makeGetRequest manager url = do
  initReq <- HC.parseRequest url
  let req =
        initReq
          { HC.method = "GET",
            HC.requestHeaders = []
          }

  result <- try @HttpException $ HC.httpLbs req manager
  case result of
    Left e -> pure $ Left (0, T.pack $ show e)
    Right resp -> do
      let status = HT.statusCode $ HC.responseStatus resp
      if status >= 200 && status < 300
        then pure $ Right $ HC.responseBody resp
        else pure $ Left (status, decodeBody $ HC.responseBody resp)

-- | Make a streaming POST request to Triton
makeStreamingRequest :: HC.Manager -> String -> LBS.ByteString -> StreamCallback -> IO (Either (Int, Text) ())
makeStreamingRequest manager url body callback = do
  initReq <- HC.parseRequest url
  let req =
        initReq
          { HC.method = "POST",
            HC.requestHeaders =
              [ ("Content-Type", "application/json")
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

-- ════════════════════════════════════════════════════════════════════════════
--                                                          // error handling
-- ════════════════════════════════════════════════════════════════════════════

-- | Classify HTTP error into ProviderError
-- Local Triton errors are typically connectivity issues
classifyError :: (Int, Text) -> ProviderResult a
classifyError (status, msg)
  | status == 404 = Retry $ ModelNotFoundError msg -- Model not loaded in Triton
  | status >= 500 = Retry $ ProviderUnavailable msg
  | status >= 400 = Failure $ InvalidRequestError msg
  | status == 0 = Retry $ TimeoutError msg -- Connection refused/timeout
  | otherwise = Failure $ UnknownError msg
