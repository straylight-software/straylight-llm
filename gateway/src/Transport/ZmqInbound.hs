-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                     // straylight-llm // transport // zmq inbound
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The sky above the port was the color of television, tuned to a dead
--      channel."
--
--                                                              — Neuromancer
--
-- ZMQ ROUTER socket for receiving SIGIL-encoded LLM requests from Straylight
-- products (omegacode, strayforge, converge).
--
-- This is the inbound path — apps send SIGIL frames here, we decode them,
-- route through providers, and respond. The outbound path (streaming responses)
-- uses the PUB socket in Transport.Zmq.
--
-- Wire format (ZMQ multipart):
--   [0] identity   : ZMQ routing identity (set by ROUTER)
--   [1] empty      : delimiter frame (ZMQ convention)
--   [2] request_id : client-generated request ID for correlation
--   [3] metadata   : JSON {"model", "stream", "timeout", ...}
--   [4] payload    : JSON ChatRequest (SIGIL encoding for messages is future work)
--
-- Response format (ZMQ multipart):
--   [0] identity   : echoed back for routing
--   [1] empty      : delimiter
--   [2] request_id : echoed back for correlation
--   [3] status     : "ok" | "error"
--   [4] payload    : JSON ChatResponse or error message
--
-- For streaming: client subscribes to PUB socket with topic "stream/<request_id>"
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Transport.ZmqInbound
  ( -- * Receiver lifecycle
    SigilReceiver,
    withSigilReceiver,
    newSigilReceiver,
    closeSigilReceiver,

    -- * Receiving requests
    SigilRequest (..),
    receiveRequest,
    parseRequest,

    -- * Sending responses
    sendResponse,
    sendError,

    -- * Configuration
    InboundConfig (..),
    defaultInboundConfig,
  )
where

-- ────────────────────────────────────────────────────────────────────────────
--                                                                 // imports
-- ────────────────────────────────────────────────────────────────────────────

import Control.Exception (bracket, try, SomeException)
import Data.Aeson (FromJSON, ToJSON, eitherDecodeStrict, encode)
import Data.Aeson qualified as Aeson
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Int (Int32)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Restricted (restrict)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.ZMQ4
  ( Context,
    Router (..),
    Socket,
    bind,
    close,
    context,
    receiveMulti,
    sendMulti,
    setReceiveTimeout,
    socket,
    term,
  )

import Types (ChatRequest, ChatResponse)

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Configuration for inbound SIGIL receiver
data InboundConfig = InboundConfig
  { icBindAddress :: !Text,
    -- ^ ZMQ bind address (default: "tcp://*:5556")
    icReceiveTimeoutMs :: !Int32
    -- ^ Receive timeout in milliseconds (-1 for infinite)
  }
  deriving (Show, Eq)

-- | Default inbound configuration
defaultInboundConfig :: InboundConfig
defaultInboundConfig =
  InboundConfig
    { icBindAddress = "tcp://*:5556",
      icReceiveTimeoutMs = -1  -- block forever
    }

-- | ZMQ receiver for inbound SIGIL requests
data SigilReceiver = SigilReceiver
  { srContext :: !Context,
    srSocket :: !(Socket Router),
    srConfig :: !InboundConfig
  }

-- | Parsed inbound request
data SigilRequest = SigilRequest
  { reqIdentity :: !ByteString,
    -- ^ ZMQ routing identity (must echo back in response)
    reqRequestId :: !Text,
    -- ^ Client-generated request ID
    reqMetadata :: !RequestMetadata,
    -- ^ Request metadata
    reqChatRequest :: !ChatRequest
    -- ^ Decoded chat request
  }
  deriving (Show)

-- | Request metadata from client
data RequestMetadata = RequestMetadata
  { rmModel :: !(Maybe Text),
    -- ^ Model override (if different from ChatRequest)
    rmStream :: !Bool,
    -- ^ Whether to stream response via PUB socket
    rmTimeout :: !(Maybe Int)
    -- ^ Request timeout override in seconds
  }
  deriving (Show, Eq)

instance FromJSON RequestMetadata where
  parseJSON = Aeson.withObject "RequestMetadata" $ \v ->
    RequestMetadata
      <$> v Aeson..:? "model"
      <*> v Aeson..:? "stream" Aeson..!= False
      <*> v Aeson..:? "timeout"

instance ToJSON RequestMetadata where
  toJSON RequestMetadata {..} =
    Aeson.object
      [ "model" Aeson..= rmModel,
        "stream" Aeson..= rmStream,
        "timeout" Aeson..= rmTimeout
      ]

-- ════════════════════════════════════════════════════════════════════════════
--                                                        // receiver lifecycle
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a SIGIL receiver with bracket-style resource management
withSigilReceiver :: InboundConfig -> (SigilReceiver -> IO a) -> IO a
withSigilReceiver config action =
  bracket context term $ \ctx ->
    bracket (socket ctx Router) close $ \sock -> do
      bind sock (T.unpack (icBindAddress config))
      setReceiveTimeout (restrict (icReceiveTimeoutMs config)) sock
      action
        SigilReceiver
          { srContext = ctx,
            srSocket = sock,
            srConfig = config
          }

-- | Create a new SIGIL receiver (caller manages lifecycle)
newSigilReceiver :: InboundConfig -> IO SigilReceiver
newSigilReceiver config = do
  ctx <- context
  sock <- socket ctx Router
  bind sock (T.unpack (icBindAddress config))
  setReceiveTimeout (restrict (icReceiveTimeoutMs config)) sock
  pure
    SigilReceiver
      { srContext = ctx,
        srSocket = sock,
        srConfig = config
      }

-- | Close the SIGIL receiver and release resources
closeSigilReceiver :: SigilReceiver -> IO ()
closeSigilReceiver recv = do
  close (srSocket recv)
  term (srContext recv)

-- ════════════════════════════════════════════════════════════════════════════
--                                                       // receiving requests
-- ════════════════════════════════════════════════════════════════════════════

-- | Receive a request from the ZMQ ROUTER socket
--
-- Blocks until a request arrives. Returns Left on parse errors.
-- The caller should handle errors gracefully (log and continue).
receiveRequest :: SigilReceiver -> IO (Either Text SigilRequest)
receiveRequest recv = do
  result <- try @SomeException $ receiveMulti (srSocket recv)
  case result of
    Left err ->
      pure $ Left $ "ZMQ receive error: " <> T.pack (show err)
    Right frames ->
      pure $ parseRequest frames

-- | Parse ZMQ multipart frames into a SigilRequest
parseRequest :: [ByteString] -> Either Text SigilRequest
parseRequest frames = case frames of
  [identity, _empty, reqIdBytes, metadataBytes, payloadBytes] -> do
    -- parse request ID
    let reqId = TE.decodeUtf8Lenient reqIdBytes

    -- parse metadata
    metadata <- case eitherDecodeStrict metadataBytes of
      Left err -> Left $ "Invalid metadata JSON: " <> T.pack err
      Right m -> Right m

    -- parse chat request payload
    chatReq <- case eitherDecodeStrict payloadBytes of
      Left err -> Left $ "Invalid ChatRequest JSON: " <> T.pack err
      Right r -> Right r

    Right
      SigilRequest
        { reqIdentity = identity,
          reqRequestId = reqId,
          reqMetadata = metadata,
          reqChatRequest = chatReq
        }
  _ ->
    Left $
      "Invalid frame count: expected 5, got " <> T.pack (show (length frames))

-- ════════════════════════════════════════════════════════════════════════════
--                                                        // sending responses
-- ════════════════════════════════════════════════════════════════════════════

-- | Send a successful response back to the client
sendResponse ::
  SigilReceiver ->
  ByteString ->    -- identity (from request)
  Text ->          -- request ID (from request)
  ChatResponse ->  -- response payload
  IO ()
sendResponse recv identity reqId response = do
  let frames =
        identity
          :| [ BS.empty,                        -- delimiter
               TE.encodeUtf8 reqId,             -- request ID
               "ok",                            -- status
               BL.toStrict (encode response)    -- payload
             ]
  sendMulti (srSocket recv) frames

-- | Send an error response back to the client
sendError ::
  SigilReceiver ->
  ByteString ->  -- identity (from request)
  Text ->        -- request ID (from request)
  Text ->        -- error message
  IO ()
sendError recv identity reqId errMsg = do
  let frames =
        identity
          :| [ BS.empty,                -- delimiter
               TE.encodeUtf8 reqId,     -- request ID
               "error",                 -- status
               TE.encodeUtf8 errMsg     -- error message
             ]
  sendMulti (srSocket recv) frames
