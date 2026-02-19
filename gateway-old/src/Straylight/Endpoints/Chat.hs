{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                         // straylight // chat
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   Chat completions endpoint handler.
   cf. OpenAI POST /v1/chat/completions
-}
module Straylight.Endpoints.Chat
  ( handleChatCompletions
  ) where

import Data.Aeson
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import Data.IORef
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock (getCurrentTime, diffUTCTime, UTCTime)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.UUID (toText)
import Data.UUID.V4 (nextRandom)
import Network.HTTP.Types
import Network.Wai

import Straylight.Config
import Straylight.Middleware.Errors
import Straylight.Middleware.Logging
import Straylight.Providers.Base
import Straylight.Router
import Straylight.Streaming
import Straylight.Types


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // request // parsing
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Parsed chat completion request
data ChatCompletionReq = ChatCompletionReq
  { ccrModel       :: !Text
  , ccrMessages    :: ![ChatMessage]
  , ccrTemperature :: !(Maybe Double)
  , ccrTopP        :: !(Maybe Double)
  , ccrMaxTokens   :: !(Maybe Int)
  , ccrStream      :: !Bool
  }
  deriving stock (Show)

instance FromJSON ChatCompletionReq where
  parseJSON = withObject "ChatCompletionReq" $ \v -> ChatCompletionReq
    <$> v .:  "model"
    <*> v .:  "messages"
    <*> v .:? "temperature"
    <*> v .:? "top_p"
    <*> v .:? "max_tokens"
    <*> (fromMaybe False <$> v .:? "stream")


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // chat // handler
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Handle /v1/chat/completions endpoint
handleChatCompletions
  :: RouterState
  -> Request
  -> (Response -> IO ResponseReceived)
  -> IO ResponseReceived
handleChatCompletions rs req respond = do
  startTime <- getCurrentTime
  body <- strictRequestBody req

  case eitherDecode body of
    Left err -> respond $ badRequest $ "Invalid JSON: " <> T.pack err

    Right chatReq@ChatCompletionReq{..} -> do
      if null ccrMessages
        then respond $ badRequest "messages must not be empty"
        else if ccrStream
          then handleStreaming rs chatReq respond
          else handleNonStreaming rs chatReq startTime respond


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // non-streaming
   ════════════════════════════════════════════════════════════════════════════════ -}

handleNonStreaming
  :: RouterState
  -> ChatCompletionReq
  -> UTCTime
  -> (Response -> IO ResponseReceived)
  -> IO ResponseReceived
handleNonStreaming rs ChatCompletionReq{..} startTime respond = do
  result <- routeRequest rs ccrModel ccrMessages ccrTemperature ccrTopP ccrMaxTokens

  case result of
    ProviderSuccess chatResp ->
      respond $ responseLBS status200 jsonHeaders (encode chatResp)

    ProviderFailure ProviderError{..} -> do
      let status
            | peStatusCode >= 500 = status502
            | peStatusCode >= 400 = status400
            | otherwise = status500
      respond $ errorResponse status peMessage "backend_error"


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // streaming
   ════════════════════════════════════════════════════════════════════════════════ -}

handleStreaming
  :: RouterState
  -> ChatCompletionReq
  -> (Response -> IO ResponseReceived)
  -> IO ResponseReceived
handleStreaming rs ChatCompletionReq{..} respond = do
  reqId <- ("chatcmpl-" <>) . T.take 8 . toText <$> nextRandom
  now <- round <$> getPOSIXTime

  respond $ responseStream status200 sseHeaders $ \write flush -> do
    -- Send initial chunk with role
    let firstChunk = StreamChunk
          { scId      = reqId
          , scObject  = "chat.completion.chunk"
          , scCreated = now
          , scModel   = ccrModel
          , scChoices = [StreamChoice 0 (ChatDelta Nothing (Just RoleAssistant)) Nothing]
          }
    write $ Builder.byteString $ formatSseChunk firstChunk
    flush

    -- Stream content
    _ <- routeStreamingRequest rs ccrModel ccrMessages ccrTemperature ccrTopP ccrMaxTokens $ \chunk -> do
      write $ Builder.byteString $ formatSseChunk chunk
      flush

    -- Send final chunk
    let finalChunk = StreamChunk
          { scId      = reqId
          , scObject  = "chat.completion.chunk"
          , scCreated = now
          , scModel   = ccrModel
          , scChoices = [StreamChoice 0 (ChatDelta Nothing Nothing) (Just FinishStop)]
          }
    write $ Builder.byteString $ formatSseChunk finalChunk
    write $ Builder.byteString formatSseDone
    flush


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // helpers
   ════════════════════════════════════════════════════════════════════════════════ -}

jsonHeaders :: [Header]
jsonHeaders = [("Content-Type", "application/json")]
