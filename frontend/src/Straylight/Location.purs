-- | Browser location helpers for runtime configuration
module Straylight.Location
  ( getHostname
  , getProtocol
  , getGatewayBaseUrl
  ) where

import Prelude
import Effect (Effect)

-- | Get the current window hostname (e.g., "localhost", "192.168.1.100")
foreign import getHostname :: Effect String

-- | Get the current protocol (e.g., "http:", "https:")
foreign import getProtocol :: Effect String

-- | Get the gateway base URL using current hostname
-- Gateway runs on port 8080
getGatewayBaseUrl :: Effect String
getGatewayBaseUrl = do
  protocol <- getProtocol
  hostname <- getHostname
  -- Remove trailing colon from protocol if present
  let proto = if protocol == "https:" then "https" else "http"
  pure $ proto <> "://" <> hostname
