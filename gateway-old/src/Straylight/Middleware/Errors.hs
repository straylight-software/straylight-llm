{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                       // straylight // errors
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   OpenAI-compatible error response formatting.
   cf. OpenAI API error format
-}
module Straylight.Middleware.Errors
  ( -- // error // responses
    errorResponse
  , badRequest
  , notFound
  , serverError
  , badGateway
  , serviceUnavailable
  ) where

import Data.Aeson (encode)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import Network.HTTP.Types
import Network.Wai

import Straylight.Types


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // error // builders
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Build an error response with OpenAI-compatible format
errorResponse :: Status -> Text -> Text -> Response
errorResponse status msg errType =
  responseLBS status jsonHeaders $ encode $ ErrorResponse $ ErrorDetail
    { errMessage = msg
    , errType    = errType
    , errCode    = Nothing
    , errParam   = Nothing
    }

-- | JSON content-type headers
jsonHeaders :: [Header]
jsonHeaders = [("Content-Type", "application/json")]


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // common // errors
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | 400 Bad Request
badRequest :: Text -> Response
badRequest msg = errorResponse status400 msg "invalid_request_error"

-- | 404 Not Found
notFound :: Response
notFound = errorResponse status404 "Not found" "invalid_request_error"

-- | 500 Internal Server Error
serverError :: Text -> Response
serverError msg = errorResponse status500 msg "internal_error"

-- | 502 Bad Gateway
badGateway :: Text -> Response
badGateway msg = errorResponse status502 msg "backend_error"

-- | 503 Service Unavailable
serviceUnavailable :: Text -> Response
serviceUnavailable msg = errorResponse status503 msg "service_unavailable"
