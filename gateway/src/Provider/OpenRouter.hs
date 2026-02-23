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

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.OpenRouter
    ( -- * Provider
      makeOpenRouterProvider
    ) where

import Control.Exception (try)
import Network.HTTP.Client (HttpException)
import Data.Aeson (eitherDecode, encode)
import Data.ByteString ()
import Data.IORef (IORef, readIORef)
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Network.HTTP.Client qualified as HC
import Network.HTTP.Types qualified as HT

import Config (ProviderConfig (..))
import Effects.Graded
import Provider.Types
import Types


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | Create an OpenRouter provider
makeOpenRouterProvider :: IORef ProviderConfig -> Provider
makeOpenRouterProvider configRef = Provider
    { providerName = OpenRouter
    , providerEnabled = isEnabled configRef
    , providerChat = chat configRef
    , providerChatStream = chatStream configRef
    , providerEmbeddings = embeddings configRef
    , providerModels = models configRef
    , providerSupportsModel = supportsModel
    }

-- | Check if OpenRouter is configured
isEnabled :: IORef ProviderConfig -> GatewayM Bool
isEnabled configRef = do
    recordConfigAccess "openrouter.enabled"
    config <- liftGatewayIO $ readIORef configRef
    pure $ pcEnabled config && pcApiKey config /= Nothing

-- | Check if model is supported
-- OpenRouter supports models from many providers with provider/model format
supportsModel :: Text -> Bool
supportsModel modelId =
    -- OpenRouter uses provider/model format for most models
    -- Also supports direct model names
    "/" `T.isInfixOf` modelId ||
    any (`T.isPrefixOf` modelId)
        [ "gpt-"
        , "claude-"
        , "llama-"
        , "mistral-"
        , "mixtral-"
        , "gemini-"
        , "deepseek-"
        , "qwen-"
        , "command-"
        ]

-- | Non-streaming chat completion
chat :: IORef ProviderConfig -> RequestContext -> ChatRequest -> GatewayM (ProviderResult ChatResponse)
chat configRef ctx req = do
    recordProvider "openrouter"
    recordModel (unModelId $ crModel req)
    config <- liftGatewayIO $ readIORef configRef
    case pcApiKey config of
        Nothing -> pure $ Failure $ AuthError "OpenRouter API key not configured"
        Just apiKey -> do
            recordAuthUsage "openrouter" "api-key"
            let url = T.unpack (pcBaseUrl config) <> "/chat/completions"
            recordHttpAccess (T.pack url) "POST" Nothing
            result <- withLatency $ makeRequest (rcManager ctx) url apiKey (encode req)
            pure $ case result of
                Left err -> classifyError err
                Right body -> case eitherDecode body of
                    Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
                    Right resp -> Success resp

-- | Streaming chat completion
chatStream :: IORef ProviderConfig -> RequestContext -> ChatRequest -> StreamCallback -> GatewayM (ProviderResult ())
chatStream configRef ctx req callback = do
    recordProvider "openrouter"
    recordModel (unModelId $ crModel req)
    config <- liftGatewayIO $ readIORef configRef
    case pcApiKey config of
        Nothing -> pure $ Failure $ AuthError "OpenRouter API key not configured"
        Just apiKey -> do
            recordAuthUsage "openrouter" "api-key"
            let url = T.unpack (pcBaseUrl config) <> "/chat/completions"
                streamReq = req { crStream = Just True }
            recordHttpAccess (T.pack url) "POST" Nothing
            result <- withLatency $ makeStreamingRequest (rcManager ctx) url apiKey (encode streamReq) callback
            pure $ case result of
                Left err -> classifyError err
                Right () -> Success ()

-- | Generate embeddings
-- n.b. OpenRouter embedding support is limited
embeddings :: IORef ProviderConfig -> RequestContext -> EmbeddingRequest -> GatewayM (ProviderResult EmbeddingResponse)
embeddings _configRef _ctx _req = do
    recordProvider "openrouter"
    -- OpenRouter doesn't have great embedding support
    -- Return error to fall through to other providers or fail gracefully
    pure $ Failure $ ModelNotFoundError "OpenRouter embedding support is limited"

-- | List available models
models :: IORef ProviderConfig -> RequestContext -> GatewayM (ProviderResult ModelList)
models configRef ctx = do
    recordProvider "openrouter"
    recordConfigAccess "openrouter.models"
    config <- liftGatewayIO $ readIORef configRef
    case pcApiKey config of
        Nothing -> pure $ Failure $ AuthError "OpenRouter API key not configured"
        Just apiKey -> do
            recordAuthUsage "openrouter" "api-key"
            let url = T.unpack (pcBaseUrl config) <> "/models"
            recordHttpAccess (T.pack url) "GET" Nothing
            result <- withLatency $ makeGetRequest (rcManager ctx) url apiKey
            pure $ case result of
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
    let req = initReq
            { HC.method = "POST"
            , HC.requestHeaders =
                [ ("Content-Type", "application/json")
                , ("Authorization", "Bearer " <> encodeUtf8 apiKey)
                , ("HTTP-Referer", "https://straylight.weyl.ai")
                , ("X-Title", "straylight-llm")
                ]
            , HC.requestBody = HC.RequestBodyLBS body
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
    let req = initReq
            { HC.method = "GET"
            , HC.requestHeaders =
                [ ("Authorization", "Bearer " <> encodeUtf8 apiKey)
                , ("HTTP-Referer", "https://straylight.weyl.ai")
                , ("X-Title", "straylight-llm")
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
    let req = initReq
            { HC.method = "POST"
            , HC.requestHeaders =
                [ ("Content-Type", "application/json")
                , ("Authorization", "Bearer " <> encodeUtf8 apiKey)
                , ("HTTP-Referer", "https://straylight.weyl.ai")
                , ("X-Title", "straylight-llm")
                ]
            , HC.requestBody = HC.RequestBodyLBS body
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
    | status == 402 = Failure $ QuotaExceededError msg  -- Credits exhausted is terminal, not transient
    | status == 404 = Retry $ ModelNotFoundError msg  -- Model not found should try next provider
    | status >= 500 = Retry $ ProviderUnavailable msg
    | status >= 400 = Failure $ InvalidRequestError msg
    | status == 0 = Retry $ TimeoutError msg
    | otherwise = Failure $ UnknownError msg
