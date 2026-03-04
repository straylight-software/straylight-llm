-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                         // straylight-llm // provider/modal
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Cyberspace. A consensual hallucination experienced daily by billions."
--
--                                                              — Neuromancer
--
-- Modal provider. Serverless GPU, pay-per-second, burst capacity.
-- Custom endpoint format - requires Modal app deployment.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}

module Provider.Modal
  ( makeModalProvider,
  )
where

import Config (ProviderConfig (pcApiKey, pcBaseUrl, pcEnabled))
import Data.IORef (IORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Effects.Do qualified as G
import Effects.Graded (Full, GatewayM, liftIO', recordConfigAccess)
import Provider.Types
  ( Provider (Provider, providerChat, providerChatStream, providerEmbeddings, providerEnabled, providerModels, providerName, providerSupportsModel),
    ProviderError (InvalidRequestError),
    ProviderName (Modal),
    ProviderResult (Failure, Success),
    RequestContext,
    StreamCallback,
  )
import Types (ChatRequest, ChatResponse, EmbeddingRequest, EmbeddingResponse, ModelList (ModelList))

-- | Modal requires custom endpoint deployment - this is a stub
-- Real implementation would call user's deployed Modal app
makeModalProvider :: IORef ProviderConfig -> Provider
makeModalProvider configRef =
  Provider
    { providerName = Modal,
      providerEnabled = isEnabled configRef,
      providerChat = \_ _ -> G.do liftIO' $ pure $ Failure $ InvalidRequestError "Modal requires custom endpoint - configure pcBaseUrl",
      providerChatStream = \_ _ _ -> G.do liftIO' $ pure $ Failure $ InvalidRequestError "Modal requires custom endpoint",
      providerEmbeddings = \_ _ -> G.do liftIO' $ pure $ Failure $ InvalidRequestError "Modal requires custom endpoint",
      providerModels = \_ -> G.do liftIO' $ pure $ Success $ ModelList "list" [],
      providerSupportsModel = const False
    }

isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "modal.enabled"
  config <- liftIO' $ readIORef configRef
  -- Modal needs both API key and custom base URL
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing && pcBaseUrl config /= Nothing
