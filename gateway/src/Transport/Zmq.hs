-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                          // straylight-llm // transport // zmq
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "A year here and he still dreamed of cyberspace, hope fading nightly.
--      All the speed he took, all the turns he'd taken and the corners
--      he'd cut in Night City, and still he'd see the matrix in his sleep."
--
--                                                              — Neuromancer
--
-- ZMQ PUB socket management for SIGIL frame egress.
--
-- The gateway is the single point of truth for all LLM traffic. This module
-- provides the ZMQ transport layer for emitting clean SIGIL binary frames to
-- downstream products (omegacode, strayforge, converge).
--
-- Wire format (ZMQ multipart):
--   [0] topic      : "model/<model-name>" or "stream/<stream-id>"
--   [1] metadata   : JSON {"stream_id", "model", "request_id", "timestamp"}
--   [2] frame      : SIGIL binary frame bytes
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Transport.Zmq
  ( -- * Publisher lifecycle
    SigilPublisher,
    withSigilPublisher,
    newSigilPublisher,
    closeSigilPublisher,

    -- * Frame emission
    emitFrame,
    emitControlFrame,

    -- * Stream metadata
    StreamMetadata (..),
    newStreamMetadata,
    modelToTopic,
    streamToTopic,
  )
where

-- ────────────────────────────────────────────────────────────────────────────
--                                                                 // imports
-- ────────────────────────────────────────────────────────────────────────────

import Control.Exception (bracket)
import Data.Aeson (ToJSON (toJSON), object, (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.ZMQ4
  ( Context,
    Pub (..),
    Socket,
    bind,
    close,
    context,
    sendMulti,
    socket,
    term,
  )

import Slide.Wire.Frame
  ( Frame (..),
    FrameOp,
    finishFrame,
    newFrameBuilder,
    writeControl,
  )

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | ZMQ publisher for SIGIL frame egress
data SigilPublisher = SigilPublisher
  { spContext :: !Context,
    spSocket :: !(Socket Pub),
    spBindAddress :: !Text
  }

-- | Metadata attached to each ZMQ message for multi-stream support
data StreamMetadata = StreamMetadata
  { metaStreamId :: !Text,
    -- ^ Unique stream identifier (request ID)
    metaModel :: !Text,
    -- ^ Model name (e.g., "anthropic/claude-sonnet-4")
    metaRequestId :: !Text,
    -- ^ Original request ID for correlation
    metaTimestamp :: !Double
    -- ^ Unix timestamp
  }
  deriving (Show, Eq)

instance ToJSON StreamMetadata where
  toJSON meta =
    object
      [ "stream_id" .= metaStreamId meta,
        "model" .= metaModel meta,
        "request_id" .= metaRequestId meta,
        "timestamp" .= metaTimestamp meta
      ]

-- ════════════════════════════════════════════════════════════════════════════
--                                                        // publisher lifecycle
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a SIGIL publisher with bracket-style resource management
--
-- Usage:
--   withSigilPublisher "tcp://*:5555" $ \publisher -> do
--       emitFrame publisher meta frame
withSigilPublisher :: Text -> (SigilPublisher -> IO a) -> IO a
withSigilPublisher bindAddr action =
  bracket context term $ \ctx ->
    bracket (socket ctx Pub) close $ \sock -> do
      bind sock (T.unpack bindAddr)
      action
        SigilPublisher
          { spContext = ctx,
            spSocket = sock,
            spBindAddress = bindAddr
          }

-- | Create a new SIGIL publisher (caller manages lifecycle)
--
-- IMPORTANT: Call closeSigilPublisher when done
newSigilPublisher :: Text -> IO SigilPublisher
newSigilPublisher bindAddr = do
  ctx <- context
  sock <- socket ctx Pub
  bind sock (T.unpack bindAddr)
  pure
    SigilPublisher
      { spContext = ctx,
        spSocket = sock,
        spBindAddress = bindAddr
      }

-- | Close the SIGIL publisher and release resources
closeSigilPublisher :: SigilPublisher -> IO ()
closeSigilPublisher pub = do
  close (spSocket pub)
  term (spContext pub)

-- ════════════════════════════════════════════════════════════════════════════
--                                                          // frame emission
-- ════════════════════════════════════════════════════════════════════════════

-- | Emit a SIGIL frame over ZMQ
--
-- ZMQ multipart format:
--   [0] topic: "model/<model-name>"
--   [1] metadata: JSON
--   [2] frame: SIGIL binary bytes
emitFrame :: SigilPublisher -> StreamMetadata -> Frame -> IO ()
emitFrame pub meta frame = do
  let frameByteString = frameBytes frame
      topic = modelToTopic (metaModel meta)
      metaJson = BS.toStrict (Aeson.encode meta)
  sendMulti (spSocket pub) (topic :| [metaJson, frameByteString])

-- | Emit a control frame (single opcode)
emitControlFrame :: SigilPublisher -> StreamMetadata -> FrameOp -> IO ()
emitControlFrame pub meta frameOp = do
  builder <- newFrameBuilder 16
  writeControl builder frameOp
  frame <- finishFrame builder
  emitFrame pub meta frame

-- ════════════════════════════════════════════════════════════════════════════
--                                                        // metadata helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Create new stream metadata with current timestamp
newStreamMetadata :: Text -> Text -> Text -> IO StreamMetadata
newStreamMetadata streamId model requestId = do
  timestamp <- getPOSIXTime
  pure
    StreamMetadata
      { metaStreamId = streamId,
        metaModel = model,
        metaRequestId = requestId,
        metaTimestamp = realToFrac timestamp
      }

-- | Create ZMQ topic from model name
--
-- Example: "anthropic/claude-sonnet-4" -> "model/anthropic/claude-sonnet-4"
modelToTopic :: Text -> ByteString
modelToTopic model = TE.encodeUtf8 ("model/" <> model)

-- | Create ZMQ topic from stream ID
--
-- Example: "req-abc123" -> "stream/req-abc123"
streamToTopic :: Text -> ByteString
streamToTopic streamId = TE.encodeUtf8 ("stream/" <> streamId)
