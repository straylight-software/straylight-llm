{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                    // straylight // streaming
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   SSE streaming utilities for chat completions.
   cf. OpenAI streaming response format
-}
module Straylight.Streaming
  ( -- // sse // formatting
    formatSseChunk
  , formatSseDone
    -- // response // helpers
  , sseHeaders
  ) where

import Data.Aeson (encode)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Network.HTTP.Types (Header)

import Straylight.Types


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // sse // formatting
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Format a stream chunk as an SSE event
formatSseChunk :: StreamChunk -> BS.ByteString
formatSseChunk chunk =
  "data: " <> LBS.toStrict (encode chunk) <> "\n\n"

-- | Format the SSE done message
formatSseDone :: BS.ByteString
formatSseDone = "data: [DONE]\n\n"


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // response // headers
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Standard SSE response headers
sseHeaders :: [Header]
sseHeaders =
  [ ("Content-Type", "text/event-stream")
  , ("Cache-Control", "no-cache")
  , ("Connection", "keep-alive")
  , ("X-Accel-Buffering", "no")  -- n.b. for nginx proxy
  ]
