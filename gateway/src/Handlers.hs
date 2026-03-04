-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                            // straylight-llm // handlers
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Night City was like a deranged experiment in social Darwinism,
--      designed by a bored researcher who kept one thumb permanently
--      on the fast-forward button."
--
--                                                              — Neuromancer
--
-- Servant handlers for the OpenAI-compatible gateway API.
-- Routes requests through the provider fallback chain.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeOperators #-}

module Handlers
  ( -- * Server
    server,
    GatewayServer,

    -- * Individual Handlers
    healthHandler,
    chatHandler,
    chatStreamHandler,
    anthropicMessagesHandler,
    completionsHandler,
    embeddingsHandler,
    modelsHandler,
    proofHandler,
    proofVerifyHandler,
    providersStatusHandler,
    metricsHandler,
    prometheusMetricsHandler,
    requestsHandler,
    requestDetailHandler,
    eventsHandler,
    configGetHandler,
    configPutHandler,
    dashboardHandler,
  )
where

import Api
import Coeffect.Types (DischargeProof, dpSignature)
import Config
  ( Config (cfgAnthropic, cfgBaseten, cfgHost, cfgLogLevel, cfgOpenRouter, cfgPort, cfgTriton, cfgVenice, cfgVertex),
    ProviderConfig (pcBaseUrl, pcEnabled),
    cfgAdminApiKey,
  )
import Control.Concurrent.STM (atomically, readTChan)
import Control.Exception (finally)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Object, eitherDecode, encode, object, toJSON, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Builder (byteString, lazyByteString, string8)
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import Data.Word (Word64)
import Network.HTTP.Types (status200, status400)
import Network.Wai (getRequestBodyChunk, responseStream)
import Numeric (showHex)
import Provider.Types
  ( ProviderError
      ( AuthError,
        InternalError,
        InvalidRequestError,
        ModelNotFoundError,
        ProviderUnavailable,
        QuotaExceededError,
        RateLimitError,
        TimeoutError,
        UnknownError
      ),
    ProviderName (Anthropic, Baseten, OpenRouter, Triton, Venice, Vertex),
  )
import Resilience.Backpressure (tryWithRequestSlot)
import Resilience.Cache (cacheRecentValues)
import Resilience.CircuitBreaker (CircuitState (Closed, HalfOpen, Open), CircuitStats, csLastFailure, csState)
import Resilience.Metrics (LatencyBuckets (lbCount, lbLe05, lbLe1, lbLe25, lbLe5, lbSum), Metrics (mProviders, mRequestsActive, mRequestsTotal, mStartTime), ProviderMetrics (pmErrorsAuth, pmErrorsOther, pmErrorsRateLimit, pmErrorsTimeout, pmErrorsUnavailable, pmLatency, pmRequestsTotal), renderPrometheus)
import Router
import Security.ConstantTime (constantTimeCompareText)
import Servant
import System.IO (hPutStrLn, stderr)
import System.Random (randomIO)
import Types
import Types.Anthropic qualified as Anthropic

-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // server
-- ════════════════════════════════════════════════════════════════════════════

-- | Server type
type GatewayServer = Server GatewayAPI

-- | Combined server implementation
server :: Router -> GatewayServer
server router =
  healthHandler
    :<|> chatHandler router
    :<|> chatStreamHandler router
    :<|> anthropicMessagesHandler router
    :<|> completionsHandler router
    :<|> embeddingsHandler router
    :<|> modelsHandler router
    :<|> proofHandler router
    :<|> proofVerifyHandler router
    :<|> providersStatusHandler router
    :<|> metricsHandler router
    :<|> prometheusMetricsHandler router
    :<|> requestsHandler router
    :<|> requestDetailHandler router
    :<|> eventsHandler router
    :<|> configGetHandler router
    :<|> configPutHandler router
    :<|> dashboardHandler router

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // handlers
-- ════════════════════════════════════════════════════════════════════════════

-- | Health check handler
healthHandler :: Handler HealthResponse
healthHandler = pure $ HealthResponse "ok" "0.1.0"

-- | Generate a unique request ID
generateRequestId :: IO Text
generateRequestId = do
  n <- randomIO :: IO Word64
  pure $ "req_" <> T.pack (showHex n "")

-- | Chat completions handler
-- Routes through provider chain: Venice -> Vertex -> Baseten -> OpenRouter
-- Returns X-Request-Id header for proof retrieval via GET /v1/proof/:requestId
chatHandler :: Router -> Maybe Text -> ChatRequest -> Handler (Headers '[Header "X-Request-Id" Text] ChatResponse)
chatHandler router _mAuth req = do
  requestId <- liftIO generateRequestId

  -- Route through provider chain
  result <- liftIO $ routeChat router requestId req

  case result of
    Right response -> pure $ addHeader requestId response
    Left err -> throwError $ toServantError err

-- ════════════════════════════════════════════════════════════════════════════
--                                              // anthropic messages handler
-- ════════════════════════════════════════════════════════════════════════════

-- | Anthropic Messages API handler
-- Accepts Anthropic-native request format (POST /v1/messages)
-- Converts to OpenAI format, routes through provider chain, converts response back
-- This allows clients using the Anthropic SDK to route through straylight-llm
anthropicMessagesHandler ::
  Router ->
  Maybe Text -> -- Authorization header
  Maybe Text -> -- x-api-key header (Anthropic style)
  Anthropic.ChatRequest ->
  Handler (Headers '[Header "X-Request-Id" Text] Anthropic.ChatResponse)
anthropicMessagesHandler router _mAuth _mApiKey anthropicReq = do
  requestId <- liftIO generateRequestId

  -- Convert Anthropic request to OpenAI format
  let openAiReq = anthropicToOpenAI anthropicReq

  -- Route through provider chain
  result <- liftIO $ routeChat router requestId openAiReq

  case result of
    Right openAiResp -> do
      -- Convert OpenAI response back to Anthropic format
      let anthropicResp = openAIToAnthropic openAiResp (Anthropic.crModel anthropicReq)
      pure $ addHeader requestId anthropicResp
    Left err -> throwError $ toServantError err

-- | Convert Anthropic ChatRequest to OpenAI ChatRequest
anthropicToOpenAI :: Anthropic.ChatRequest -> ChatRequest
anthropicToOpenAI Anthropic.ChatRequest {..} =
  ChatRequest
    { crModel = ModelId crModel,
      crMessages = systemMessage ++ concatMap convertMessage crMessages,
      crTemperature = fmap Temperature crTemperature,
      crMaxTokens = Just (MaxTokens crMaxTokens),
      crMaxCompletionTokens = Nothing,
      crTopP = Nothing,
      crN = Nothing,
      crStream = Just crStream,
      crStop = Nothing,
      crPresencePenalty = Nothing,
      crFrequencyPenalty = Nothing,
      crLogitBias = Nothing,
      crUser = Nothing,
      crTools = fmap (map convertTool) crTools,
      crToolChoice = Nothing,
      crSeed = Nothing,
      crResponseFormat = Nothing
    }
  where
    -- System message goes as a separate message in OpenAI format
    systemMessage = case crSystem of
      Just sys -> [Message System (Just $ TextContent sys) Nothing Nothing Nothing]
      Nothing -> []

    -- Convert a single Anthropic message to OpenAI message(s)
    convertMessage :: Anthropic.Message -> [Message]
    convertMessage Anthropic.Message {..} =
      [Message (convertRole msgRole) (Just $ convertContent msgContent) Nothing Nothing Nothing]

    convertRole :: Anthropic.Role -> Role
    convertRole Anthropic.User = User
    convertRole Anthropic.Assistant = Assistant
    convertRole Anthropic.System = System

    convertContent :: Anthropic.Content -> MessageContent
    convertContent (Anthropic.SimpleContent txt) = TextContent txt
    convertContent (Anthropic.BlockContent blocks) =
      -- For block content, concatenate text blocks
      TextContent $ T.concat [t | Anthropic.TextBlock t <- blocks]

    convertTool :: Anthropic.ToolDefinition -> ToolDef
    convertTool Anthropic.ToolDefinition {..} =
      ToolDef
        { toolType = "function",
          toolFunction =
            ToolFunction
              { tfName = tdName,
                tfDescription = tdDescription,
                tfParameters = fmap convertSchema tisProperties,
                tfStrict = Nothing
              }
        }
      where
        Anthropic.ToolInputSchema {..} = tdInputSchema

    convertSchema :: Object -> JsonSchema
    convertSchema obj = JsonSchema obj

-- | Convert OpenAI ChatResponse to Anthropic ChatResponse
openAIToAnthropic :: ChatResponse -> Text -> Anthropic.ChatResponse
openAIToAnthropic ChatResponse {..} model =
  Anthropic.ChatResponse
    { Anthropic.respId = unResponseId respId,
      Anthropic.respModel = model,
      Anthropic.respRole = Anthropic.Assistant,
      Anthropic.respContent = extractContent,
      Anthropic.respStopReason = convertStopReason,
      Anthropic.respUsage =
        Anthropic.Usage
          { Anthropic.usageInputTokens = maybe 0 usagePromptTokens respUsage,
            Anthropic.usageOutputTokens = maybe 0 usageCompletionTokens respUsage,
            Anthropic.usageCacheRead = Nothing,
            Anthropic.usageCacheWrite = Nothing
          }
    }
  where
    extractContent :: [Anthropic.ContentBlock]
    extractContent = case respChoices of
      (Choice {..} : _) -> case msgContent choiceMessage of
        Just (TextContent txt) -> [Anthropic.TextBlock txt]
        Just (PartsContent _) -> [] -- Could expand this
        Nothing -> []
      [] -> []

    convertStopReason :: Maybe Anthropic.StopReason
    convertStopReason = case respChoices of
      (Choice {..} : _) -> case choiceFinishReason of
        Just (FinishReason "stop") -> Just Anthropic.EndTurn
        Just (FinishReason "length") -> Just Anthropic.MaxTokens
        Just (FinishReason "tool_calls") -> Just Anthropic.ToolUseSR
        _ -> Just Anthropic.EndTurn
      [] -> Nothing

-- ════════════════════════════════════════════════════════════════════════════
--                                                        // streaming handler
-- ════════════════════════════════════════════════════════════════════════════

-- | Streaming chat completions handler (SSE)
-- Uses WAI responseStream for Server-Sent Events
-- POST /v1/chat/completions/stream
chatStreamHandler :: Router -> Tagged Handler Application
chatStreamHandler router = Tagged $ \req respond' -> do
  -- Read and accumulate request body
  bodyRef <- newIORef LBS.empty
  let readBody = do
        chunk <- getRequestBodyChunk req
        if BS.null chunk
          then readIORef bodyRef
          else do
            atomicModifyIORef' bodyRef $ \acc -> (acc <> LBS.fromStrict chunk, ())
            readBody

  bodyBytes <- readBody

  -- Parse the ChatRequest from JSON
  case eitherDecode bodyBytes of
    Left parseErr ->
      respond'
        $ responseStream
          status400
          [("Content-Type", "application/json")]
        $ \send flush -> do
          send $
            lazyByteString $
              encode $
                ApiError $
                  ErrorDetail
                    (T.pack $ "Invalid JSON: " ++ parseErr)
                    "invalid_request"
                    Nothing
                    Nothing
          flush
    Right chatReq -> do
      requestId <- generateRequestId

      -- Start SSE response
      respond'
        $ responseStream
          status200
          [ ("Content-Type", "text/event-stream"),
            ("Cache-Control", "no-cache"),
            ("Connection", "keep-alive"),
            ("X-Request-Id", TE.encodeUtf8 requestId)
          ]
        $ \send flush -> do
          -- Callback that sends each chunk as SSE
          let streamCallback chunk = do
                send $ string8 "data: "
                send $ byteString chunk
                send $ string8 "\n\n"
                flush

          -- Route through provider chain with streaming
          result <- routeChatStream router requestId chatReq streamCallback

          -- Send final event based on result
          case result of
            Right () -> do
              -- Send [DONE] marker (OpenAI convention)
              send $ string8 "data: [DONE]\n\n"
              flush
            Left err -> do
              -- Send error as SSE event
              send $ string8 "data: "
              send $ lazyByteString $ encode $ streamErrorToJson err
              send $ string8 "\n\n"
              flush
  where
    streamErrorToJson :: ProviderError -> ApiError
    streamErrorToJson err =
      ApiError $
        ErrorDetail
          (providerErrorMessage err)
          (providerErrorType err)
          Nothing
          Nothing

    providerErrorMessage :: ProviderError -> Text
    providerErrorMessage (AuthError msg) = msg
    providerErrorMessage (RateLimitError msg) = msg
    providerErrorMessage (QuotaExceededError msg) = msg
    providerErrorMessage (ModelNotFoundError msg) = msg
    providerErrorMessage (ProviderUnavailable msg) = msg
    providerErrorMessage (InvalidRequestError msg) = msg
    providerErrorMessage (InternalError msg) = msg
    providerErrorMessage (TimeoutError msg) = msg
    providerErrorMessage (UnknownError msg) = msg

    providerErrorType :: ProviderError -> Text
    providerErrorType (AuthError _) = "authentication_error"
    providerErrorType (RateLimitError _) = "rate_limit_error"
    providerErrorType (QuotaExceededError _) = "quota_exceeded"
    providerErrorType (ModelNotFoundError _) = "model_not_found"
    providerErrorType (ProviderUnavailable _) = "provider_unavailable"
    providerErrorType (InvalidRequestError _) = "invalid_request"
    providerErrorType (InternalError _) = "internal_error"
    providerErrorType (TimeoutError _) = "timeout"
    providerErrorType (UnknownError _) = "internal_error"

-- | Legacy completions handler
-- Converts to chat format and routes through chain
completionsHandler :: Router -> Maybe Text -> CompletionRequest -> Handler CompletionResponse
completionsHandler router _mAuth req = do
  requestId <- liftIO generateRequestId

  -- Convert completion request to chat request
  let chatReq =
        ChatRequest
          { crModel = complModel req,
            crMessages =
              [ Message
                  { msgRole = User,
                    msgContent = Just $ TextContent $ complPrompt req,
                    msgName = Nothing,
                    msgToolCallId = Nothing,
                    msgToolCalls = Nothing
                  }
              ],
            crTemperature = complTemperature req,
            crTopP = complTopP req,
            crN = complN req,
            crStream = complStream req,
            crStop = complStop req,
            crMaxTokens = complMaxTokens req,
            crMaxCompletionTokens = Nothing,
            crPresencePenalty = complPresencePenalty req,
            crFrequencyPenalty = complFrequencyPenalty req,
            crLogitBias = Nothing,
            crUser = complUser req,
            crTools = Nothing,
            crToolChoice = Nothing,
            crResponseFormat = Nothing,
            crSeed = Nothing
          }

  result <- liftIO $ routeChat router requestId chatReq

  case result of
    Right chatResp -> do
      -- Convert chat response back to completion format
      let text = extractText chatResp
      pure
        CompletionResponse
          { complRespId = respId chatResp,
            complRespObject = "text_completion",
            complRespCreated = respCreated chatResp,
            complRespModel = respModel chatResp,
            complRespChoices =
              [ CompletionChoice
                  { ccText = text,
                    ccIndex = 0,
                    ccFinishReason = choiceFinishReason =<< safeHead (respChoices chatResp)
                  }
              ],
            complRespUsage = respUsage chatResp
          }
    Left err -> throwError $ toServantError err
  where
    extractText resp =
      case respChoices resp of
        [] -> ""
        (choice : _) ->
          case msgContent (choiceMessage choice) of
            Just (TextContent t) -> t
            _ -> ""

    safeHead [] = Nothing
    safeHead (x : _) = Just x

-- | Embeddings handler
embeddingsHandler :: Router -> Maybe Text -> EmbeddingRequest -> Handler EmbeddingResponse
embeddingsHandler router _mAuth req = do
  requestId <- liftIO generateRequestId

  result <- liftIO $ routeEmbeddings router requestId req

  case result of
    Right response -> pure response
    Left err -> throwError $ toServantError err

-- | Models handler
-- Returns models from all enabled providers
modelsHandler :: Router -> Maybe Text -> Handler ModelList
modelsHandler router _mAuth = do
  requestId <- liftIO generateRequestId

  result <- liftIO $ routeModels router requestId

  case result of
    Right response -> pure response
    Left err -> throwError $ toServantError err

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // error mapping
-- ════════════════════════════════════════════════════════════════════════════

-- | Convert ProviderError to Servant ServerError
toServantError :: ProviderError -> ServerError
toServantError err = case err of
  AuthError msg -> err401 {errBody = encodeError "authentication_error" msg}
  RateLimitError msg -> err429 {errBody = encodeError "rate_limit_error" msg}
  QuotaExceededError msg -> err402 {errBody = encodeError "quota_exceeded" msg}
  ModelNotFoundError msg -> err404 {errBody = encodeError "model_not_found" msg}
  ProviderUnavailable msg -> err503 {errBody = encodeError "provider_unavailable" msg}
  InvalidRequestError msg -> err400 {errBody = encodeError "invalid_request" msg}
  InternalError msg -> err500 {errBody = encodeError "internal_error" msg}
  TimeoutError msg -> err504 {errBody = encodeError "timeout" msg}
  UnknownError msg -> err500 {errBody = encodeError "internal_error" msg}
  where
    encodeError :: Text -> Text -> LBS.ByteString
    encodeError typ msg = encode $ ApiError $ ErrorDetail msg typ Nothing Nothing

-- ════════════════════════════════════════════════════════════════════════════
--                                                               // proof api
-- ════════════════════════════════════════════════════════════════════════════

-- | Discharge proof handler
-- GET /v1/proof/:requestId
proofHandler :: Router -> Text -> Handler DischargeProof
proofHandler router requestId = do
  mProof <- liftIO $ lookupProof router requestId
  case mProof of
    Just proof -> pure proof
    Nothing ->
      throwError
        err404
          { errBody =
              encode $
                ApiError $
                  ErrorDetail
                    ("Proof not found for request: " <> requestId)
                    "proof_not_found"
                    Nothing
                    Nothing
          }

-- ════════════════════════════════════════════════════════════════════════════
--                                                     // observability handlers
-- ════════════════════════════════════════════════════════════════════════════

-- | Verify admin authentication
-- Returns 401 if auth header missing or invalid
requireAdminAuth :: Router -> Maybe Text -> Text -> Handler ()
requireAdminAuth router mAuthHeader endpoint = do
  case cfgAdminApiKey (routerConfig router) of
    Nothing ->
      -- No admin key configured - reject all admin requests
      throwError
        err401
          { errBody =
              encode $
                ApiError $
                  ErrorDetail
                    "Admin API key not configured (set ADMIN_API_KEY environment variable)"
                    "admin_key_not_configured"
                    Nothing
                    Nothing
          }
    Just adminKey -> do
      case mAuthHeader of
        Nothing ->
          throwError
            err401
              { errBody =
                  encode $
                    ApiError $
                      ErrorDetail
                        "Admin authentication required (Authorization header missing)"
                        "authentication_required"
                        Nothing
                        Nothing
              }
        Just authHeader -> do
          -- Support both "Bearer <key>" and raw key
          let providedKey = case T.stripPrefix "Bearer " authHeader of
                Just k -> k
                Nothing -> authHeader

          -- SECURITY: Constant-time comparison prevents timing attacks
          if not (constantTimeCompareText providedKey adminKey)
            then
              throwError
                err401
                  { errBody =
                      encode $
                        ApiError $
                          ErrorDetail
                            "Invalid admin API key"
                            "invalid_admin_key"
                            Nothing
                            Nothing
                  }
            else do
              -- Audit log to stderr (structured logging)
              liftIO $
                hPutStrLn stderr $
                  "[ADMIN_ACCESS] endpoint="
                    <> T.unpack endpoint
                    <> " auth=success"
              pure ()

-- | Providers status handler (admin only)
-- GET /v1/admin/providers/status
providersStatusHandler :: Router -> Maybe Text -> Handler ProvidersStatusResponse
providersStatusHandler router mAuth = do
  requireAdminAuth router mAuth "providers/status"

  -- Rate limit admin endpoint
  mResult <- liftIO $ tryWithRequestSlot (routerAdminSemaphore router) $ do
    getProviderCircuitStats router

  case mResult of
    Nothing ->
      throwError
        err503
          { errBody =
              encode $
                ApiError $
                  ErrorDetail
                    "Admin endpoint overloaded (too many concurrent requests)"
                    "rate_limited"
                    Nothing
                    Nothing
          }
    Just stats -> do
      let providerStatuses =
            map
              ( \(name, circuitStats) ->
                  ProviderStatus name (csState circuitStats) circuitStats
              )
              stats
      pure $ ProvidersStatusResponse providerStatuses

-- | Metrics handler (admin only)
-- GET /v1/admin/metrics
metricsHandler :: Router -> Maybe Text -> Handler MetricsResponse
metricsHandler router mAuth = do
  requireAdminAuth router mAuth "metrics"

  -- Rate limit admin endpoint
  mResult <- liftIO $ tryWithRequestSlot (routerAdminSemaphore router) $ do
    getRouterMetrics router

  case mResult of
    Nothing ->
      throwError
        err503
          { errBody =
              encode $
                ApiError $
                  ErrorDetail
                    "Admin endpoint overloaded (too many concurrent requests)"
                    "rate_limited"
                    Nothing
                    Nothing
          }
    Just metrics ->
      pure $ MetricsResponse metrics

-- | Prometheus metrics handler (no auth required)
-- GET /metrics — standard Prometheus scrape endpoint
prometheusMetricsHandler :: Router -> Handler Text
prometheusMetricsHandler router = do
  metrics <- liftIO $ getRouterMetrics router
  pure $ renderPrometheus metrics

-- | Requests handler (admin only)
-- GET /v1/admin/requests?limit=N
requestsHandler :: Router -> Maybe Text -> Maybe Int -> Handler RequestsResponse
requestsHandler router mAuth mLimit = do
  requireAdminAuth router mAuth "requests"

  -- Rate limit admin endpoint
  mResult <- liftIO $ tryWithRequestSlot (routerAdminSemaphore router) $ do
    -- Apply limit (default 100, max 1000)
    let limit = maybe 100 (min 1000) mLimit

    -- Get recent request history from cache
    recentRequests <- cacheRecentValues (routerRequestHistory router) limit

    pure (recentRequests, limit)

  case mResult of
    Nothing ->
      throwError
        err503
          { errBody =
              encode $
                ApiError $
                  ErrorDetail
                    "Admin endpoint overloaded (too many concurrent requests)"
                    "rate_limited"
                    Nothing
                    Nothing
          }
    Just (recentRequests, _) -> do
      -- Convert to JSON values
      let requestValues = map toJSON recentRequests

      pure $ RequestsResponse requestValues (length recentRequests)

-- ════════════════════════════════════════════════════════════════════════════
--                                                         // new api handlers
-- ════════════════════════════════════════════════════════════════════════════

-- | Single request detail handler (admin only)
-- GET /v1/admin/requests/:requestId
requestDetailHandler :: Router -> Text -> Maybe Text -> Handler RequestDetailResponse
requestDetailHandler router requestId mAuth = do
  requireAdminAuth router mAuth "requests/detail"

  -- Look up in request history cache
  mHistory <- liftIO $ lookupRequestHistory router requestId

  case mHistory of
    Nothing ->
      throwError
        err404
          { errBody =
              encode $
                ApiError $
                  ErrorDetail
                    ("Request not found: " <> requestId)
                    "request_not_found"
                    Nothing
                    Nothing
          }
    Just history -> do
      -- Also try to get the proof
      mProof <- liftIO $ lookupProof router requestId
      let proofJson = fmap toJSON mProof

      pure $
        RequestDetailResponse
          { rdrRequestId = rhRequestId history,
            rdrModel = rhModel history,
            rdrProvider = fmap (T.pack . show) (rhProvider history),
            rdrSuccess = rhSuccess history,
            rdrLatencyMs = rhLatencyMs history,
            rdrTimestamp = rhTimestamp history,
            rdrProof = proofJson
          }

-- | Proof verification handler
-- POST /v1/proof/:requestId/verify
proofVerifyHandler :: Router -> Text -> Handler ProofVerifyResponse
proofVerifyHandler router requestId = do
  mProof <- liftIO $ lookupProof router requestId

  case mProof of
    Nothing ->
      throwError
        err404
          { errBody =
              encode $
                ApiError $
                  ErrorDetail
                    ("Proof not found for request: " <> requestId)
                    "proof_not_found"
                    Nothing
                    Nothing
          }
    Just proof -> do
      -- Check if proof has a signature
      case dpSignature proof of
        Nothing ->
          pure $
            ProofVerifyResponse
              { pvrValid = False,
                pvrMessage = "Proof is unsigned (no signing key configured)",
                pvrDetails = Nothing
              }
        Just _sig -> do
          -- TODO: Implement actual ed25519 signature verification
          -- For now, we just check that the signature exists
          pure $
            ProofVerifyResponse
              { pvrValid = True,
                pvrMessage = "Proof signature present (verification pending signing key)",
                pvrDetails = Just $ toJSON proof
              }

-- | Real-time events handler (SSE stream)
-- GET /v1/events
-- Subscribes to the event broadcaster and streams events to the client
eventsHandler :: Router -> Tagged Handler Application
eventsHandler router = Tagged $ \_req respond' -> do
  -- n.b. CORS headers added by middleware in Main.hs, don't duplicate here
  respond'
    $ responseStream
      status200
      [ ("Content-Type", "text/event-stream"),
        ("Cache-Control", "no-cache"),
        ("Connection", "keep-alive")
      ]
    $ \send flush -> do
      -- Subscribe to the event broadcaster
      (subId, subChan, cleanup) <- subscribe (routerEventBroadcaster router)

      -- Send initial connection event
      send $ string8 "event: connected\n"
      send $ string8 "data: {\"status\":\"connected\",\"subscriber_id\":\""
      send $ string8 $ show subId -- Include subscriber ID for debugging
      send $ string8 "\"}\n\n"
      flush

      -- Log subscription
      hPutStrLn stderr $ "[SSE] Client subscribed: " ++ show subId

      -- Event loop: read from channel and send to client
      -- Cleanup on disconnect
      flip finally cleanup $ eventLoop send flush subChan
  where
    eventLoop send flush subChan = do
      -- Block waiting for next event
      event <- atomically $ readTChan subChan

      -- Encode and send the event
      let encoded = encodeSSEEvent event
      _ <- send $ lazyByteString encoded
      _ <- flush

      -- Continue loop
      eventLoop send flush subChan

-- | Config get handler (admin only)
-- GET /v1/admin/config
configGetHandler :: Router -> Maybe Text -> Handler ConfigResponse
configGetHandler router mAuth = do
  requireAdminAuth router mAuth "config"

  let cfg = routerConfig router

  -- Build provider status list
  let providerConfigs =
        [ toJSON $
            object
              [ "name" .= ("venice" :: Text),
                "enabled" .= (pcEnabled $ cfgVenice cfg),
                "base_url" .= (pcBaseUrl $ cfgVenice cfg)
              ],
          toJSON $
            object
              [ "name" .= ("vertex" :: Text),
                "enabled" .= (pcEnabled $ cfgVertex cfg)
              ],
          toJSON $
            object
              [ "name" .= ("baseten" :: Text),
                "enabled" .= (pcEnabled $ cfgBaseten cfg)
              ],
          toJSON $
            object
              [ "name" .= ("openrouter" :: Text),
                "enabled" .= (pcEnabled $ cfgOpenRouter cfg)
              ],
          toJSON $
            object
              [ "name" .= ("anthropic" :: Text),
                "enabled" .= (pcEnabled $ cfgAnthropic cfg)
              ]
        ]

  pure $
    ConfigResponse
      { crPort = cfgPort cfg,
        crHost = cfgHost cfg,
        crLogLevel = cfgLogLevel cfg,
        crProviders = providerConfigs
      }

-- | Config put handler (admin only)
-- PUT /v1/admin/config
configPutHandler :: Router -> Maybe Text -> ConfigUpdateRequest -> Handler ConfigResponse
configPutHandler router mAuth _updateReq = do
  requireAdminAuth router mAuth "config/update"

  -- TODO: Implement runtime config updates
  -- For now, just return the current config (read-only)
  liftIO $ hPutStrLn stderr "[CONFIG] Config update requested but not yet implemented"

  -- Return current config
  configGetHandler router mAuth

-- | Dashboard handler (admin only)
-- GET /v1/admin/dashboard — aggregate provider health view
dashboardHandler :: Router -> Maybe Text -> Handler DashboardResponse
dashboardHandler router mAuth = do
  requireAdminAuth router mAuth "dashboard"

  -- Rate limit admin endpoint
  mResult <- liftIO $ tryWithRequestSlot (routerAdminSemaphore router) $ do
    -- Get current time for uptime calculation
    now <- getCurrentTime

    -- Get metrics snapshot
    metrics <- getRouterMetrics router

    -- Get circuit breaker stats for all providers
    circuitStats <- getProviderCircuitStats router

    -- Build provider health list
    let cfg = routerConfig router
        providerHealths = buildProviderHealths cfg metrics circuitStats

    -- Calculate uptime
    let uptimeSeconds = realToFrac (diffUTCTime now (mStartTime metrics)) :: Double

    pure
      ( now,
        uptimeSeconds,
        providerHealths,
        fromIntegral (mRequestsTotal metrics) :: Int,
        mRequestsActive metrics
      )

  case mResult of
    Nothing ->
      throwError
        err503
          { errBody =
              encode $
                ApiError $
                  ErrorDetail
                    "Admin endpoint overloaded (too many concurrent requests)"
                    "rate_limited"
                    Nothing
                    Nothing
          }
    Just (now, uptimeSeconds, providerHealths, totalReqs, activeReqs) ->
      pure $
        DashboardResponse
          { drTimestamp = T.pack $ iso8601Show now,
            drUptime = uptimeSeconds,
            drProviders = providerHealths,
            drTotalRequests = totalReqs,
            drActiveRequests = activeReqs,
            drCacheHitRate = Nothing -- TODO: Add cache hit rate tracking
          }

-- | Build ProviderHealth list from metrics and circuit breaker stats
buildProviderHealths :: Config -> Metrics -> [(ProviderName, CircuitStats)] -> [ProviderHealth]
buildProviderHealths cfg metrics circuitStats =
  let providerConfigs =
        [ (Triton, cfgTriton cfg),
          (Venice, cfgVenice cfg),
          (Vertex, cfgVertex cfg),
          (Baseten, cfgBaseten cfg),
          (OpenRouter, cfgOpenRouter cfg),
          (Anthropic, cfgAnthropic cfg)
        ]
   in map (buildProviderHealth metrics circuitStats) providerConfigs

-- | Build a single ProviderHealth from provider config, metrics and circuit stats
buildProviderHealth :: Metrics -> [(ProviderName, CircuitStats)] -> (ProviderName, ProviderConfig) -> ProviderHealth
buildProviderHealth metrics circuitStats (name, providerCfg) =
  let -- Look up circuit breaker stats
      mCircuitStats = lookup name circuitStats
      circuitState = maybe Closed csState mCircuitStats

      -- Look up provider metrics
      mProviderMetrics = Map.lookup name (mProviders metrics)

      -- Calculate request/error counts
      requestCount = maybe 0 (fromIntegral . pmRequestsTotal) mProviderMetrics
      errorCount = maybe 0 totalErrors mProviderMetrics

      -- Calculate error rate
      errorRate =
        if requestCount > 0
          then fromIntegral errorCount / fromIntegral requestCount
          else 0.0

      -- Calculate latencies
      (avgLatency, p50, p95, p99) = case mProviderMetrics of
        Nothing -> (Nothing, Nothing, Nothing, Nothing)
        Just pm ->
          let lb = pmLatency pm
              count = lbCount lb
           in if count == 0
                then (Nothing, Nothing, Nothing, Nothing)
                else
                  let avgMs = (lbSum lb / fromIntegral count) * 1000.0
                      -- Approximate percentiles from histogram buckets
                      -- p50: ~50% of requests <= this value
                      p50Ms = estimatePercentile lb 0.50 * 1000.0
                      p95Ms = estimatePercentile lb 0.95 * 1000.0
                      p99Ms = estimatePercentile lb 0.99 * 1000.0
                   in (Just avgMs, Just p50Ms, Just p95Ms, Just p99Ms)

      -- Calculate health score (0-100)
      healthScore = calculateHealthScore circuitState errorRate

      -- Get last error info from circuit breaker
      lastError = case mCircuitStats of
        Nothing -> Nothing
        Just cs -> case csLastFailure cs of
          Nothing -> Nothing
          Just _ts -> Just "Recent failure recorded" -- We don't store the message
   in ProviderHealth
        { phName = name,
          phEnabled = pcEnabled providerCfg,
          phCircuitState = circuitState,
          phHealthScore = healthScore,
          phLatencyAvg = avgLatency,
          phLatencyP50 = p50,
          phLatencyP95 = p95,
          phLatencyP99 = p99,
          phErrorRate = errorRate,
          phRequestCount = requestCount,
          phErrorCount = errorCount,
          phLastError = lastError
        }

-- | Calculate total errors from ProviderMetrics
totalErrors :: ProviderMetrics -> Int
totalErrors pm =
  fromIntegral $
    pmErrorsAuth pm
      + pmErrorsRateLimit pm
      + pmErrorsTimeout pm
      + pmErrorsUnavailable pm
      + pmErrorsOther pm

-- | Calculate health score (0-100) based on circuit state and error rate
calculateHealthScore :: CircuitState -> Double -> Double
calculateHealthScore circuitState errorRate =
  let baseScore = case circuitState of
        Closed -> 100.0
        HalfOpen -> 50.0
        Open -> 0.0
      -- Reduce score based on error rate (up to 50 points)
      errorPenalty = min 50.0 (errorRate * 100.0)
   in max 0.0 (baseScore - errorPenalty)

-- | Estimate latency percentile from histogram buckets
-- This is an approximation since we only have bucket counts
estimatePercentile :: LatencyBuckets -> Double -> Double
estimatePercentile lb percentile =
  let count = lbCount lb
      target = floor (fromIntegral count * percentile) :: Int
      -- Check buckets in order to find where target falls
      -- Buckets: 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
      buckets =
        [ (0.005, lbLe05 lb), -- Note: lbLe005 would be 5ms but we'll use available buckets
          (0.050, lbLe05 lb),
          (0.100, lbLe1 lb),
          (0.250, lbLe25 lb),
          (0.500, lbLe5 lb)
        ]
   in -- Simple estimation: find first bucket that exceeds target
      case dropWhile (\(_, c) -> fromIntegral c < target) buckets of
        [] -> 10.0 -- Fallback: assume > 10s
        ((latency, _) : _) -> latency
