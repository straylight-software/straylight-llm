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
      server
    , GatewayServer

      -- * Individual Handlers
    , healthHandler
    , chatHandler
    , completionsHandler
    , embeddingsHandler
    , modelsHandler
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import Data.Word (Word64)
import Numeric (showHex)
import Servant
import System.Random (randomIO)

import Data.Aeson (encode)
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T

import Api
import Provider.Types (ProviderError (..))
import Router
import Types


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
    :<|> completionsHandler router
    :<|> embeddingsHandler router
    :<|> modelsHandler router


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
chatHandler :: Router -> Maybe Text -> ChatRequest -> Handler ChatResponse
chatHandler router _mAuth req = do
    requestId <- liftIO generateRequestId

    -- Route through provider chain
    result <- liftIO $ routeChat router requestId req

    case result of
        Right response -> pure response
        Left err -> throwError $ toServantError err

-- | Legacy completions handler
-- Converts to chat format and routes through chain
completionsHandler :: Router -> Maybe Text -> CompletionRequest -> Handler CompletionResponse
completionsHandler router _mAuth req = do
    requestId <- liftIO generateRequestId

    -- Convert completion request to chat request
    let chatReq = ChatRequest
            { crModel = complModel req
            , crMessages =
                [ Message
                    { msgRole = User
                    , msgContent = Just $ TextContent $ complPrompt req
                    , msgName = Nothing
                    , msgToolCallId = Nothing
                    , msgToolCalls = Nothing
                    }
                ]
            , crTemperature = complTemperature req
            , crTopP = complTopP req
            , crN = complN req
            , crStream = complStream req
            , crStop = complStop req
            , crMaxTokens = complMaxTokens req
            , crMaxCompletionTokens = Nothing
            , crPresencePenalty = complPresencePenalty req
            , crFrequencyPenalty = complFrequencyPenalty req
            , crLogitBias = Nothing
            , crUser = complUser req
            , crTools = Nothing
            , crToolChoice = Nothing
            , crResponseFormat = Nothing
            , crSeed = Nothing
            }

    result <- liftIO $ routeChat router requestId chatReq

    case result of
        Right chatResp -> do
            -- Convert chat response back to completion format
            let text = extractText chatResp
            pure CompletionResponse
                { complRespId = respId chatResp
                , complRespObject = "text_completion"
                , complRespCreated = respCreated chatResp
                , complRespModel = respModel chatResp
                , complRespChoices =
                    [ CompletionChoice
                        { ccText = text
                        , ccIndex = 0
                        , ccFinishReason = choiceFinishReason =<< safeHead (respChoices chatResp)
                        }
                    ]
                , complRespUsage = respUsage chatResp
                }
        Left err -> throwError $ toServantError err
  where
    extractText resp =
        case respChoices resp of
            [] -> ""
            (choice:_) ->
                case msgContent (choiceMessage choice) of
                    Just (TextContent t) -> t
                    _ -> ""

    safeHead [] = Nothing
    safeHead (x:_) = Just x

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
    AuthError msg -> err401 { errBody = encodeError "authentication_error" msg }
    RateLimitError msg -> err429 { errBody = encodeError "rate_limit_error" msg }
    QuotaExceededError msg -> err402 { errBody = encodeError "quota_exceeded" msg }
    ModelNotFoundError msg -> err404 { errBody = encodeError "model_not_found" msg }
    ProviderUnavailable msg -> err503 { errBody = encodeError "provider_unavailable" msg }
    InvalidRequestError msg -> err400 { errBody = encodeError "invalid_request" msg }
    InternalError msg -> err500 { errBody = encodeError "internal_error" msg }
    TimeoutError msg -> err504 { errBody = encodeError "timeout" msg }
    UnknownError msg -> err500 { errBody = encodeError "internal_error" msg }
  where
    encodeError :: Text -> Text -> LBS.ByteString
    encodeError typ msg = encode $ ApiError $ ErrorDetail msg typ Nothing Nothing
