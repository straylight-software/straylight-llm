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

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.Venice
    ( -- * Provider
      makeVeniceProvider
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

import Config (ProviderConfig (pcEnabled, pcApiKey, pcBaseUrl))
import Effects.Graded
import Provider.Types
import Types


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | Supported Venice models (subset - Venice supports many models)
veniceModels :: [Text]
veniceModels =
    [ "llama-3.3-70b"
    , "llama-3.1-405b"
    , "deepseek-r1"
    , "deepseek-r1-671b"
    , "qwen-2.5-coder"
    , "dolphin-2.9.2-qwen2-72b"
    ]

-- | Create a Venice AI provider
makeVeniceProvider :: IORef ProviderConfig -> Provider
makeVeniceProvider configRef = Provider
    { providerName = Venice
    , providerEnabled = isEnabled configRef
    , providerChat = chat configRef
    , providerChatStream = chatStream configRef
    , providerEmbeddings = embeddings configRef
    , providerModels = models configRef
    , providerSupportsModel = supportsModel
    }

-- | Check if Venice is configured
isEnabled :: IORef ProviderConfig -> GatewayM Bool
isEnabled configRef = do
    recordConfigAccess "venice.enabled"
    config <- liftGatewayIO $ readIORef configRef
    pure $ pcEnabled config && pcApiKey config /= Nothing

-- | Check if model is supported
supportsModel :: Text -> Bool
supportsModel modelId =
    -- Venice supports these model prefixes
    any (`T.isPrefixOf` modelId)
        [ "llama-"
        , "deepseek-"
        , "qwen-"
        , "dolphin-"
        , "mistral-"
        ]

-- | Non-streaming chat completion
chat :: IORef ProviderConfig -> RequestContext -> ChatRequest -> GatewayM (ProviderResult ChatResponse)
chat configRef ctx req = do
    recordProvider "venice"
    recordModel (unModelId $ crModel req)
    config <- liftGatewayIO $ readIORef configRef
    case pcApiKey config of
        Nothing -> pure $ Failure $ AuthError "Venice API key not configured"
        Just apiKey -> do
            recordAuthUsage "venice" "api-key"
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
    recordProvider "venice"
    recordModel (unModelId $ crModel req)
    config <- liftGatewayIO $ readIORef configRef
    case pcApiKey config of
        Nothing -> pure $ Failure $ AuthError "Venice API key not configured"
        Just apiKey -> do
            recordAuthUsage "venice" "api-key"
            let url = T.unpack (pcBaseUrl config) <> "/chat/completions"
                streamReq = req { crStream = Just True }
            recordHttpAccess (T.pack url) "POST" Nothing
            result <- withLatency $ makeStreamingRequest (rcManager ctx) url apiKey (encode streamReq) callback
            pure $ case result of
                Left err -> classifyError err
                Right () -> Success ()

-- | Generate embeddings
embeddings :: IORef ProviderConfig -> RequestContext -> EmbeddingRequest -> GatewayM (ProviderResult EmbeddingResponse)
embeddings configRef ctx req = do
    recordProvider "venice"
    recordModel (unModelId $ embModel req)
    config <- liftGatewayIO $ readIORef configRef
    case pcApiKey config of
        Nothing -> pure $ Failure $ AuthError "Venice API key not configured"
        Just apiKey -> do
            recordAuthUsage "venice" "api-key"
            let url = T.unpack (pcBaseUrl config) <> "/embeddings"
            recordHttpAccess (T.pack url) "POST" Nothing
            result <- withLatency $ makeRequest (rcManager ctx) url apiKey (encode req)
            pure $ case result of
                Left err -> classifyError err
                Right body -> case eitherDecode body of
                    Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
                    Right resp -> Success resp

-- | List available models
models :: IORef ProviderConfig -> RequestContext -> GatewayM (ProviderResult ModelList)
models configRef ctx = do
    recordProvider "venice"
    recordConfigAccess "venice.models"
    config <- liftGatewayIO $ readIORef configRef
    case pcApiKey config of
        Nothing -> pure $ Failure $ AuthError "Venice API key not configured"
        Just apiKey -> do
            recordAuthUsage "venice" "api-key"
            let url = T.unpack (pcBaseUrl config) <> "/models"
            recordHttpAccess (T.pack url) "GET" Nothing
            result <- withLatency $ makeGetRequest (rcManager ctx) url apiKey
            pure $ case result of
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
    let req = initReq
            { HC.method = "POST"
            , HC.requestHeaders =
                [ ("Content-Type", "application/json")
                , ("Authorization", "Bearer " <> encodeUtf8 apiKey)
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
