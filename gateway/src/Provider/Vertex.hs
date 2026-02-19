-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                      // straylight-llm // provider/vertex
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The Sprawl was a long strange way from home."
--
--                                                              — Neuromancer
--
-- Vertex AI (Google Cloud) provider backend. Secondary provider in the
-- fallback chain. Uses Google Cloud OAuth for authentication, not API keys.
--
-- Vertex AI OpenAI-compatible endpoint:
--   https://{location}-aiplatform.googleapis.com/v1/projects/{project}/
--   locations/{location}/endpoints/openapi/chat/completions
--
-- Authentication: Uses Application Default Credentials (ADC) or service
-- account key via GOOGLE_APPLICATION_CREDENTIALS environment variable.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.Vertex
    ( -- * Provider
      makeVertexProvider

      -- * OAuth
    , getAccessToken
    ) where

import Control.Concurrent.MVar (MVar, newMVar, modifyMVar)
import Control.Exception (SomeException, try)
import Data.Aeson (eitherDecode, encode)
import Data.Aeson qualified as Aeson
import Data.ByteString (ByteString)
import Data.IORef (IORef, readIORef)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time.Clock (UTCTime, getCurrentTime, addUTCTime)
import System.Process (readProcess)

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Network.HTTP.Client qualified as HC
import Network.HTTP.Types qualified as HT

import Config (ProviderConfig (..), VertexConfig (..))
import Provider.Types
import Types


-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // oauth
-- ════════════════════════════════════════════════════════════════════════════

-- | Cached OAuth token with expiry
data TokenCache = TokenCache
    { tcToken :: Text
    , tcExpiry :: UTCTime
    }

-- | Get an access token using gcloud CLI or service account
-- Caches the token and refreshes when expired
getAccessToken :: MVar (Maybe TokenCache) -> Maybe FilePath -> IO (Either Text Text)
getAccessToken cacheVar _mServiceAccountPath = do
    now <- getCurrentTime
    
    -- Check cache first
    cached <- modifyMVar cacheVar $ \mCache -> do
        case mCache of
            Just cache | tcExpiry cache > now ->
                -- Token still valid, return it
                pure (mCache, Just $ tcToken cache)
            _ ->
                -- Need to refresh
                pure (Nothing, Nothing)
    
    case cached of
        Just token -> pure $ Right token
        Nothing -> do
            -- Get fresh token using gcloud
            -- n.b. In production, would use service account JSON directly
            -- but gcloud auth application-default print-access-token works
            -- in containers with mounted credentials
            result <- try @SomeException $
                readProcess "gcloud" ["auth", "application-default", "print-access-token"] ""
            
            case result of
                Left e -> pure $ Left $ "Failed to get access token: " <> T.pack (show e)
                Right tokenStr -> do
                    let token = T.strip $ T.pack tokenStr
                    -- Cache for 55 minutes (tokens last 60 min)
                    expiry <- addUTCTime (55 * 60) <$> getCurrentTime
                    _ <- modifyMVar cacheVar $ \_ ->
                        pure (Just $ TokenCache token expiry, ())
                    pure $ Right token


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a Vertex AI provider
makeVertexProvider :: IORef ProviderConfig -> IO Provider
makeVertexProvider configRef = do
    -- Create token cache
    tokenCache <- newMVar Nothing
    
    pure Provider
        { providerName = Vertex
        , providerEnabled = isEnabled configRef
        , providerChat = chat configRef tokenCache
        , providerChatStream = chatStream configRef tokenCache
        , providerEmbeddings = embeddings configRef tokenCache
        , providerModels = models configRef tokenCache
        , providerSupportsModel = supportsModel
        }

-- | Check if Vertex is configured
isEnabled :: IORef ProviderConfig -> IO Bool
isEnabled configRef = do
    config <- readIORef configRef
    case pcVertexConfig config of
        Nothing -> pure False
        Just vc -> pure $ pcEnabled config && not (T.null $ vcProjectId vc)

-- | Check if model is supported
-- Vertex supports Gemini models and some partner models
supportsModel :: Text -> Bool
supportsModel modelId =
    any (`T.isPrefixOf` modelId)
        [ "gemini-"
        , "claude-"  -- Anthropic via Model Garden
        , "llama-"   -- Meta via Model Garden
        ]

-- | Get the base URL for Vertex AI
getVertexBaseUrl :: VertexConfig -> Text
getVertexBaseUrl vc =
    "https://" <> vcLocation vc <> "-aiplatform.googleapis.com/v1/projects/"
    <> vcProjectId vc <> "/locations/" <> vcLocation vc <> "/endpoints/openapi"

-- | Non-streaming chat completion
chat :: IORef ProviderConfig -> MVar (Maybe TokenCache) -> RequestContext -> ChatRequest -> IO (ProviderResult ChatResponse)
chat configRef tokenCache ctx req = do
    config <- readIORef configRef
    case pcVertexConfig config of
        Nothing -> pure $ Failure $ AuthError "Vertex AI not configured"
        Just vc -> do
            tokenResult <- getAccessToken tokenCache (vcServiceAccountKeyPath vc)
            case tokenResult of
                Left err -> pure $ Failure $ AuthError err
                Right token -> do
                    let url = T.unpack (getVertexBaseUrl vc) <> "/chat/completions"
                    result <- makeRequest (rcManager ctx) url token (encode req)
                    pure $ case result of
                        Left err -> classifyError err
                        Right body -> case eitherDecode body of
                            Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
                            Right resp -> Success resp

-- | Streaming chat completion
chatStream :: IORef ProviderConfig -> MVar (Maybe TokenCache) -> RequestContext -> ChatRequest -> StreamCallback -> IO (ProviderResult ())
chatStream configRef tokenCache ctx req callback = do
    config <- readIORef configRef
    case pcVertexConfig config of
        Nothing -> pure $ Failure $ AuthError "Vertex AI not configured"
        Just vc -> do
            tokenResult <- getAccessToken tokenCache (vcServiceAccountKeyPath vc)
            case tokenResult of
                Left err -> pure $ Failure $ AuthError err
                Right token -> do
                    let url = T.unpack (getVertexBaseUrl vc) <> "/chat/completions"
                        streamReq = req { crStream = Just True }
                    result <- makeStreamingRequest (rcManager ctx) url token (encode streamReq) callback
                    pure $ case result of
                        Left err -> classifyError err
                        Right () -> Success ()

-- | Generate embeddings
embeddings :: IORef ProviderConfig -> MVar (Maybe TokenCache) -> RequestContext -> EmbeddingRequest -> IO (ProviderResult EmbeddingResponse)
embeddings configRef tokenCache ctx req = do
    config <- readIORef configRef
    case pcVertexConfig config of
        Nothing -> pure $ Failure $ AuthError "Vertex AI not configured"
        Just vc -> do
            tokenResult <- getAccessToken tokenCache (vcServiceAccountKeyPath vc)
            case tokenResult of
                Left err -> pure $ Failure $ AuthError err
                Right token -> do
                    let url = T.unpack (getVertexBaseUrl vc) <> "/embeddings"
                    result <- makeRequest (rcManager ctx) url token (encode req)
                    pure $ case result of
                        Left err -> classifyError err
                        Right body -> case eitherDecode body of
                            Left parseErr -> Failure $ UnknownError $ "Parse error: " <> T.pack parseErr
                            Right resp -> Success resp

-- | List available models
-- n.b. Vertex doesn't have a direct /models endpoint like OpenAI
-- Return a static list of known Vertex models
models :: IORef ProviderConfig -> MVar (Maybe TokenCache) -> RequestContext -> IO (ProviderResult ModelList)
models configRef _tokenCache _ctx = do
    config <- readIORef configRef
    case pcVertexConfig config of
        Nothing -> pure $ Failure $ AuthError "Vertex AI not configured"
        Just _ -> do
            -- Return static list of Vertex AI models
            let vertexModels =
                    [ Model "gemini-2.0-flash" "model" 0 "google"
                    , Model "gemini-2.0-pro" "model" 0 "google"
                    , Model "gemini-1.5-flash" "model" 0 "google"
                    , Model "gemini-1.5-pro" "model" 0 "google"
                    , Model "claude-3-5-sonnet@20240620" "model" 0 "anthropic"
                    , Model "claude-3-opus@20240229" "model" 0 "anthropic"
                    ]
            pure $ Success $ ModelList "list" vertexModels


-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // http
-- ════════════════════════════════════════════════════════════════════════════

-- | Make a POST request with OAuth Bearer token
makeRequest :: HC.Manager -> String -> Text -> LBS.ByteString -> IO (Either (Int, Text) LBS.ByteString)
makeRequest manager url token body = do
    initReq <- HC.parseRequest url
    let req = initReq
            { HC.method = "POST"
            , HC.requestHeaders =
                [ ("Content-Type", "application/json")
                , ("Authorization", "Bearer " <> encodeUtf8 token)
                ]
            , HC.requestBody = HC.RequestBodyLBS body
            }

    result <- try @SomeException $ HC.httpLbs req manager
    case result of
        Left e -> pure $ Left (0, T.pack $ show e)
        Right resp -> do
            let status = HT.statusCode $ HC.responseStatus resp
            if status >= 200 && status < 300
                then pure $ Right $ HC.responseBody resp
                else pure $ Left (status, decodeBody $ HC.responseBody resp)

-- | Make a streaming POST request
makeStreamingRequest :: HC.Manager -> String -> Text -> LBS.ByteString -> StreamCallback -> IO (Either (Int, Text) ())
makeStreamingRequest manager url token body callback = do
    initReq <- HC.parseRequest url
    let req = initReq
            { HC.method = "POST"
            , HC.requestHeaders =
                [ ("Content-Type", "application/json")
                , ("Authorization", "Bearer " <> encodeUtf8 token)
                ]
            , HC.requestBody = HC.RequestBodyLBS body
            }

    result <- try @SomeException $ HC.withResponse req manager $ \resp -> do
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
    | status == 401 = Retry $ AuthError msg    -- Token expired, retry with refresh
    | status == 403 = Failure $ AuthError msg  -- Permission denied
    | status == 429 = Retry $ RateLimitError msg
    | status == 404 = Failure $ ModelNotFoundError msg
    | status >= 500 = Retry $ ProviderUnavailable msg
    | status >= 400 = Failure $ InvalidRequestError msg
    | status == 0 = Retry $ TimeoutError msg
    | otherwise = Failure $ UnknownError msg
