{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                  // straylight // openrouter
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   OpenRouter fallback backend implementation.
   cf. https://openrouter.ai/docs

   Used when CGP is unavailable or returns 5xx errors.
-}
module Straylight.Providers.OpenRouter
  ( -- // provider // interface
    OpenRouterProvider (..)
  , newOpenRouterProvider
    -- // operations
  , orHealth
  , orChatCompletion
  , orChatCompletionStream
  ) where

import Control.Exception (SomeException, catch)
import Data.Aeson
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Network.HTTP.Client as HC
import Network.HTTP.Types (statusCode, RequestHeaders)

import Straylight.Config
import Straylight.Providers.Base
import Straylight.Types


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // openrouter // provider
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | OpenRouter provider state
data OpenRouterProvider = OpenRouterProvider
  { orpConfig  :: !OpenRouterConfig
  , orpManager :: !HttpManager
  }


-- | Create a new OpenRouter provider
newOpenRouterProvider :: OpenRouterConfig -> IO OpenRouterProvider
newOpenRouterProvider cfg = do
  mgr <- createHttpManager (orTimeout cfg)
  pure OpenRouterProvider
    { orpConfig  = cfg
    , orpManager = mgr
    }


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // health // check
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Check if the OpenRouter backend is reachable.
--   n.b. OpenRouter doesn't have a dedicated health endpoint,
--   so we check if API key is configured
orHealth :: OpenRouterProvider -> IO Bool
orHealth OpenRouterProvider{..} =
  pure $ case orApiKey orpConfig of
    Just k  -> not $ T.null k
    Nothing -> False


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // chat // completion
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Chat completion request payload
data ChatRequest = ChatRequest
  { crModel       :: !Text
  , crMessages    :: ![ChatMessage]
  , crTemperature :: !(Maybe Double)
  , crTopP        :: !(Maybe Double)
  , crMaxTokens   :: !(Maybe Int)
  , crStream      :: !Bool
  }

instance ToJSON ChatRequest where
  toJSON ChatRequest{..} = object
    [ "model"       .= crModel
    , "messages"    .= crMessages
    , "temperature" .= crTemperature
    , "top_p"       .= crTopP
    , "max_tokens"  .= crMaxTokens
    , "stream"      .= crStream
    ]

-- | Send a chat completion request to OpenRouter (non-streaming)
orChatCompletion
  :: OpenRouterProvider
  -> Text           -- ^ model
  -> [ChatMessage]  -- ^ messages
  -> Maybe Double   -- ^ temperature
  -> Maybe Double   -- ^ top_p
  -> Maybe Int      -- ^ max_tokens
  -> IO (ProviderResult ChatResponse)
orChatCompletion OpenRouterProvider{..} model messages temp topP maxTokens = do
  let url = T.unpack (orApiBase orpConfig) <> "/v1/chat/completions"
      body = encode ChatRequest
        { crModel       = mapModel orpConfig model
        , crMessages    = messages
        , crTemperature = temp
        , crTopP        = topP
        , crMaxTokens   = maxTokens
        , crStream      = False
        }

  result <- (do
    initReq <- HC.parseRequest url
    let req = initReq
          { HC.method = "POST"
          , HC.requestBody = HC.RequestBodyLBS body
          , HC.requestHeaders = buildHeaders orpConfig
          }
    resp <- HC.httpLbs req orpManager
    let status = statusCode (HC.responseStatus resp)
    if status >= 200 && status < 300
      then case eitherDecode (HC.responseBody resp) of
        Right chatResp -> pure $ ProviderSuccess chatResp
        Left err       -> pure $ ProviderFailure $ mkProviderError
          ("JSON decode error: " <> T.pack err) 500
      else pure $ ProviderFailure $ mkProviderError
        ("OpenRouter error: " <> T.pack (show status)) status)
    `catch` \(e :: SomeException) ->
      pure $ ProviderFailure $ mkConnectionError $ "OpenRouter error: " <> T.pack (show e)

  pure result


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // streaming // completion
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Send a streaming chat completion request to OpenRouter
orChatCompletionStream
  :: OpenRouterProvider
  -> Text           -- ^ model
  -> [ChatMessage]  -- ^ messages
  -> Maybe Double   -- ^ temperature
  -> Maybe Double   -- ^ top_p
  -> Maybe Int      -- ^ max_tokens
  -> (StreamChunk -> IO ())  -- ^ chunk handler
  -> IO (ProviderResult ())
orChatCompletionStream OpenRouterProvider{..} model messages temp topP maxTokens onChunk = do
  let url = T.unpack (orApiBase orpConfig) <> "/v1/chat/completions"
      body = encode ChatRequest
        { crModel       = mapModel orpConfig model
        , crMessages    = messages
        , crTemperature = temp
        , crTopP        = topP
        , crMaxTokens   = maxTokens
        , crStream      = True
        }

  result <- (do
    initReq <- HC.parseRequest url
    let req = initReq
          { HC.method = "POST"
          , HC.requestBody = HC.RequestBodyLBS body
          , HC.requestHeaders = buildHeaders orpConfig
          }

    HC.withResponse req orpManager $ \resp -> do
      let status = statusCode (HC.responseStatus resp)
      if status >= 200 && status < 300
        then do
          processStream (HC.responseBody resp) onChunk
          pure $ ProviderSuccess ()
        else pure $ ProviderFailure $ mkProviderError
          ("OpenRouter stream error: " <> T.pack (show status)) status)
    `catch` \(e :: SomeException) ->
      pure $ ProviderFailure $ mkConnectionError $ "OpenRouter error: " <> T.pack (show e)

  pure result


{- ────────────────────────────────────────────────────────────────────────────────
                                                        // stream // processing
   ──────────────────────────────────────────────────────────────────────────────── -}

-- | Process SSE stream from response body
processStream :: HC.BodyReader -> (StreamChunk -> IO ()) -> IO ()
processStream bodyReader onChunk = loop ""
  where
    loop buffer = do
      chunk <- HC.brRead bodyReader
      if LBS.null (LBS.fromStrict chunk)
        then processLine buffer onChunk
        else do
          let fullText = buffer <> TE.decodeUtf8 chunk
              allLines = T.splitOn "\n" fullText
              (completeLines, remainder) = case allLines of
                []  -> ([], "")
                xs  -> (init xs, last xs)
          mapM_ (\l -> processLine l onChunk) completeLines
          loop remainder

-- | Process a single SSE line
processLine :: Text -> (StreamChunk -> IO ()) -> IO ()
processLine line onChunk
  | "data: " `T.isPrefixOf` line = do
      let jsonPart = T.strip $ T.drop 6 line
      if jsonPart == "[DONE]"
        then pure ()
        else case eitherDecodeStrict (TE.encodeUtf8 jsonPart) of
          Right chunk -> onChunk chunk
          Left _      -> pure ()
  | otherwise = pure ()


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // helpers
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Map client model to backend model
mapModel :: OpenRouterConfig -> Text -> Text
mapModel cfg model =
  case lookup model (orModels cfg) of
    Just mapped -> mapped
    Nothing     -> model

-- | Build HTTP headers for OpenRouter request.
--   n.b. includes OpenRouter-specific headers
buildHeaders :: OpenRouterConfig -> RequestHeaders
buildHeaders cfg =
  [ ("Content-Type", "application/json")
  , ("HTTP-Referer", maybe "" TE.encodeUtf8 (orSiteUrl cfg))
  , ("X-Title", TE.encodeUtf8 $ orSiteName cfg)
  ] <> maybe [] (\k -> [("Authorization", "Bearer " <> TE.encodeUtf8 k)]) (orApiKey cfg)
