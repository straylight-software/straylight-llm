-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // straylight-llm // provider/openrouter
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd operated on an almost permanent adrenaline high, a byproduct of
--      youth and proficiency, jacked into a custom cyberspace deck that
--      projected his disembodied consciousness into the consensual
--      hallucination that was the matrix."
--
--                                                              — Neuromancer
--
-- OpenRouter provider backend. Final fallback in the provider chain.
-- OpenAI-compatible API at https://openrouter.ai/api/v1
-- Routes to 100+ models across multiple providers.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.OpenRouter
  ( -- * Provider
    makeOpenRouterProvider,
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
    ProviderName (OpenRouter),
    ProviderResult (..),
    RequestContext (..),
    StreamCallback,
  )
import Types
  ( ChatRequest (..),
    ChatResponse,
    EmbeddingRequest,
    EmbeddingResponse,
    ModelId (..),
    ModelList,
  )

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | Create an OpenRouter provider
makeOpenRouterProvider :: IORef ProviderConfig -> Provider
makeOpenRouterProvider configRef =
  Provider
    { providerName = OpenRouter,
      providerEnabled = isEnabled configRef,
      providerChat = chat configRef,
      providerChatStream = chatStream configRef,
      providerEmbeddings = embeddings configRef,
      providerModels = models configRef,
      providerSupportsModel = supportsModel
    }

-- | Check if OpenRouter is configured
isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "openrouter.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing

-- | Check if model is supported
-- OpenRouter supports models from many providers with provider/model format
supportsModel :: Text -> Bool
supportsModel modelId =
  -- OpenRouter uses provider/model format for most models
  -- Also supports direct model names
  "/" `T.isInfixOf` modelId
    || any
      (`T.isPrefixOf` modelId)
      [ "gpt-",
        "claude-",
        "llama-",
        "mistral-",
        "mixtral-",
        "gemini-",
        "deepseek-",
        "qwen-",
        "command-"
      ]

-- | Non-streaming chat completion
chat :: IORef ProviderConfig -> RequestContext -> ChatRequest -> GatewayM Full (ProviderResult ChatResponse)
chat configRef ctx req = G.do
  recordProvider "openrouter"
  recordModel (unModelId $ crModel req)
  config <- liftIO' $ readIORef configRef
  chatWithConfig config ctx req

-- | Chat implementation after config is loaded
chatWithConfig :: ProviderConfig -> RequestContext -> ChatRequest -> GatewayM Full (ProviderResult ChatResponse)
chatWithConfig config ctx req =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "OpenRouter API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "openrouter" "api-key"
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
  recordProvider "openrouter"
  recordModel (unModelId $ crModel req)
  config <- liftIO' $ readIORef configRef
  chatStreamWithConfig config ctx req callback

-- | Streaming chat implementation after config is loaded
chatStreamWithConfig :: ProviderConfig -> RequestContext -> ChatRequest -> StreamCallback -> GatewayM Full (ProviderResult ())
chatStreamWithConfig config ctx req callback =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "OpenRouter API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "openrouter" "api-key"
      let url = T.unpack (pcBaseUrl config) <> "/chat/completions"
          streamReq = req {crStream = Just True}
      recordHttpAccess (T.pack url) "POST" Nothing
      result <- withLatency $ makeStreamingRequest (rcManager ctx) url apiKey (encode streamReq) callback
      liftIO' $ pure $ case result of
        Left err -> classifyError err
        Right () -> Success ()

-- | Generate embeddings
-- n.b. OpenRouter embedding support is limited
embeddings :: IORef ProviderConfig -> RequestContext -> EmbeddingRequest -> GatewayM Full (ProviderResult EmbeddingResponse)
embeddings _configRef _ctx _req = G.do
  recordProvider "openrouter"
  -- OpenRouter doesn't have great embedding support
  -- Return error to fall through to other providers or fail gracefully
  liftIO' $ pure $ Failure $ ModelNotFoundError "OpenRouter embedding support is limited"

-- | List available models
models :: IORef ProviderConfig -> RequestContext -> GatewayM Full (ProviderResult ModelList)
models configRef ctx = G.do
  recordProvider "openrouter"
  recordConfigAccess "openrouter.models"
  config <- liftIO' $ readIORef configRef
  modelsWithConfig config ctx

-- | Models implementation after config is loaded
modelsWithConfig :: ProviderConfig -> RequestContext -> GatewayM Full (ProviderResult ModelList)
modelsWithConfig config ctx =
  case pcApiKey config of
    Nothing -> liftIO' $ pure $ Failure $ AuthError "OpenRouter API key not configured"
    Just apiKey -> G.do
      recordAuthUsage "openrouter" "api-key"
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

-- | Make a POST request with OpenRouter-specific headers
makeRequest :: HC.Manager -> String -> Text -> LBS.ByteString -> IO (Either (Int, Text) LBS.ByteString)
makeRequest manager url apiKey body = do
  initReq <- HC.parseRequest url
  let req =
        initReq
          { HC.method = "POST",
            HC.requestHeaders =
              [ ("Content-Type", "application/json"),
                ("Authorization", "Bearer " <> encodeUtf8 apiKey),
                ("HTTP-Referer", "https://straylight.weyl.ai"),
                ("X-Title", "straylight-llm")
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
              [ ("Authorization", "Bearer " <> encodeUtf8 apiKey),
                ("HTTP-Referer", "https://straylight.weyl.ai"),
                ("X-Title", "straylight-llm")
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
                ("Authorization", "Bearer " <> encodeUtf8 apiKey),
                ("HTTP-Referer", "https://straylight.weyl.ai"),
                ("X-Title", "straylight-llm")
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
