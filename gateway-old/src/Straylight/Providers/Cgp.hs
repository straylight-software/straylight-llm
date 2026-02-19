{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                       // straylight // cgp
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   Cloud GPU Provider (CGP) backend implementation.
   n.b. primary backend — requests route here first.

   Supports any OpenAI-compatible inference server:
   vLLM, TGI, SGLang, Ollama, Triton, etc.
-}
module Straylight.Providers.Cgp
  ( -- // provider // interface
    CgpProvider (..)
  , newCgpProvider
    -- // operations
  , cgpHealth
  , cgpChatCompletion
  , cgpChatCompletionStream
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
                                                        // cgp // provider
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | CGP provider state
data CgpProvider = CgpProvider
  { cpConfig  :: !CgpConfig
  , cpManager :: !HttpManager
  }


-- | Create a new CGP provider
newCgpProvider :: CgpConfig -> IO CgpProvider
newCgpProvider cfg = do
  mgr <- createHttpManager (cgpTimeout cfg)
  pure CgpProvider
    { cpConfig  = cfg
    , cpManager = mgr
    }


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // health // check
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Check if the CGP backend is healthy
cgpHealth :: CgpProvider -> IO Bool
cgpHealth CgpProvider{..} = do
  let url = T.unpack (cgpApiBase cpConfig) <> T.unpack (cgpHealthEndpoint cpConfig)
  result <- (do
    req <- HC.parseRequest url
    resp <- HC.httpLbs req cpManager
    pure $ statusCode (HC.responseStatus resp) == 200)
    `catch` \(_ :: SomeException) -> pure False
  pure result


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

-- | Send a chat completion request to CGP (non-streaming)
cgpChatCompletion
  :: CgpProvider
  -> Text           -- ^ model
  -> [ChatMessage]  -- ^ messages
  -> Maybe Double   -- ^ temperature
  -> Maybe Double   -- ^ top_p
  -> Maybe Int      -- ^ max_tokens
  -> IO (ProviderResult ChatResponse)
cgpChatCompletion CgpProvider{..} model messages temp topP maxTokens = do
  let url = T.unpack (cgpApiBase cpConfig) <> "/v1/chat/completions"
      body = encode ChatRequest
        { crModel       = mapModel cpConfig model
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
          , HC.requestHeaders = buildHeaders cpConfig
          }
    resp <- HC.httpLbs req cpManager
    let status = statusCode (HC.responseStatus resp)
    if status >= 200 && status < 300
      then case eitherDecode (HC.responseBody resp) of
        Right chatResp -> pure $ ProviderSuccess chatResp
        Left err       -> pure $ ProviderFailure $ mkProviderError
          ("JSON decode error: " <> T.pack err) 500
      else pure $ ProviderFailure $ mkProviderError
        ("CGP error: " <> T.pack (show status)) status)
    `catch` \(e :: SomeException) ->
      pure $ ProviderFailure $ mkConnectionError $ "CGP connection error: " <> T.pack (show e)

  pure result


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // streaming // completion
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Send a streaming chat completion request to CGP
cgpChatCompletionStream
  :: CgpProvider
  -> Text           -- ^ model
  -> [ChatMessage]  -- ^ messages
  -> Maybe Double   -- ^ temperature
  -> Maybe Double   -- ^ top_p
  -> Maybe Int      -- ^ max_tokens
  -> (StreamChunk -> IO ())  -- ^ chunk handler
  -> IO (ProviderResult ())
cgpChatCompletionStream CgpProvider{..} model messages temp topP maxTokens onChunk = do
  let url = T.unpack (cgpApiBase cpConfig) <> "/v1/chat/completions"
      body = encode ChatRequest
        { crModel       = mapModel cpConfig model
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
          , HC.requestHeaders = buildHeaders cpConfig
          }

    HC.withResponse req cpManager $ \resp -> do
      let status = statusCode (HC.responseStatus resp)
      if status >= 200 && status < 300
        then do
          processStream (HC.responseBody resp) onChunk
          pure $ ProviderSuccess ()
        else pure $ ProviderFailure $ mkProviderError
          ("CGP stream error: " <> T.pack (show status)) status)
    `catch` \(e :: SomeException) ->
      pure $ ProviderFailure $ mkConnectionError $ "CGP stream error: " <> T.pack (show e)

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
        then processLine buffer onChunk  -- process final buffer
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
mapModel :: CgpConfig -> Text -> Text
mapModel cfg model =
  case lookup model (cgpModels cfg) of
    Just mapped -> mapped
    Nothing     -> model

-- | Build HTTP headers for CGP request
buildHeaders :: CgpConfig -> RequestHeaders
buildHeaders cfg =
  [ ("Content-Type", "application/json")
  ] <> maybe [] (\k -> [("Authorization", "Bearer " <> TE.encodeUtf8 k)]) (cgpApiKey cfg)
