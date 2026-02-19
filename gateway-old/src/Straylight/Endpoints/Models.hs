{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                       // straylight // models
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   Models endpoint handler.
   cf. OpenAI GET /v1/models
-}
module Straylight.Endpoints.Models
  ( handleModels
  ) where

import Data.Aeson (encode)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Network.HTTP.Types
import Network.Wai

import Straylight.Router
import Straylight.Types


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // models // handler
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Handle /v1/models endpoint.
--   n.b. returns a static list of supported models
handleModels :: RouterState -> IO Response
handleModels _rs = do
  now <- round <$> getPOSIXTime

  let models =
        [ ModelInfo
            { modelId      = "gpt-4"
            , modelObject  = "model"
            , modelCreated = now
            , modelOwnedBy = "straylight"
            }
        , ModelInfo
            { modelId      = "gpt-4-turbo"
            , modelObject  = "model"
            , modelCreated = now
            , modelOwnedBy = "straylight"
            }
        , ModelInfo
            { modelId      = "gpt-3.5-turbo"
            , modelObject  = "model"
            , modelCreated = now
            , modelOwnedBy = "straylight"
            }
        , ModelInfo
            { modelId      = "claude-3-opus"
            , modelObject  = "model"
            , modelCreated = now
            , modelOwnedBy = "straylight"
            }
        , ModelInfo
            { modelId      = "claude-3-sonnet"
            , modelObject  = "model"
            , modelCreated = now
            , modelOwnedBy = "straylight"
            }
        ]

      response = ModelsResponse
        { modelsObject = "list"
        , modelsData   = models
        }

  pure $ responseLBS status200 jsonHeaders (encode response)


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // helpers
   ════════════════════════════════════════════════════════════════════════════════ -}

jsonHeaders :: [Header]
jsonHeaders = [("Content-Type", "application/json")]
