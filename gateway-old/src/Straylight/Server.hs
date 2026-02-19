{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                       // straylight // server
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   "And somewhere he was laughing, in a white-painted loft,
    distant fingers caressing the deck, tears of release
    streaking his face."

                                                               — Neuromancer

   WAI application with coeffect-tracked endpoints.
-}
module Straylight.Server
  ( -- // application
    app
  , runServer
    -- // coeffect // manifest
  , coeffectManifest
  ) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (forever, void)
import Data.Aeson
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Handler.Warp
import System.IO (hFlush, stdout, hPutStrLn, stderr)

import Straylight.Coeffect
import Straylight.Config
import Straylight.Endpoints.Chat
import Straylight.Endpoints.Health
import Straylight.Endpoints.Models
import Straylight.Middleware.Errors
import Straylight.Middleware.Logging
import Straylight.Router


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // wai // application
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Main WAI application
app :: Config -> RouterState -> Application
app cfg rs req respond = do
  let path = pathInfo req
      meth = requestMethod req

  case (meth, path) of
    -- // health // endpoints
    ("GET", ["health"]) -> do
      resp <- handleHealth rs
      respond resp

    ("GET", ["ready"]) -> do
      resp <- handleReady rs
      respond resp

    -- // models // endpoint
    ("GET", ["v1", "models"]) -> do
      resp <- handleModels rs
      respond resp

    -- // chat // completions
    ("POST", ["v1", "chat", "completions"]) ->
      handleChatCompletions rs req respond

    -- // coeffect // manifest
    ("GET", ["coeffects", "manifest"]) ->
      respond $ responseLBS status200 jsonHeaders (encode coeffectManifest)

    -- // 404 // not found
    _ -> respond notFound


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // server // runner
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Run the server with configuration
runServer :: Config -> IO ()
runServer cfg = do
  -- Initialize router state
  rs <- newRouterState cfg

  -- Start health check thread
  void $ forkIO $ healthCheckLoop rs

  -- Print banner
  printBanner cfg

  -- Run Warp server
  let settings = setPort (cfgPort cfg)
               $ setHost "*"
               $ setOnException (\_ e -> hPutStrLn stderr $ "Exception: " <> show e)
               $ defaultSettings

  runSettings settings (app cfg rs)


-- | Background health check loop
healthCheckLoop :: RouterState -> IO ()
healthCheckLoop rs = forever $ do
  threadDelay 30000000  -- 30 seconds
  updateHealth rs


-- | Print startup banner
printBanner :: Config -> IO ()
printBanner cfg = do
  putStrLn ""
  putStrLn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  putStrLn "                                                   // straylight-llm //"
  putStrLn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  putStrLn ""
  putStrLn "  CGP-first OpenAI gateway with verified types"
  putStrLn "  Graded monads with coeffect equations"
  putStrLn ""
  putStrLn "════════════════════════════════════════════════════════════════════════════════"
  putStrLn "                                                          // endpoints //"
  putStrLn "════════════════════════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn $ "  http://localhost:" <> show (cfgPort cfg) <> "/v1/chat/completions    [POST]"
  putStrLn $ "  http://localhost:" <> show (cfgPort cfg) <> "/v1/models              [GET]"
  putStrLn $ "  http://localhost:" <> show (cfgPort cfg) <> "/health                 [GET]"
  putStrLn $ "  http://localhost:" <> show (cfgPort cfg) <> "/coeffects/manifest     [GET]"
  putStrLn ""
  putStrLn "════════════════════════════════════════════════════════════════════════════════"
  putStrLn "                                                          // backends //"
  putStrLn "════════════════════════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn $ "  CGP:        " <> if cgpEnabled cfg
    then T.unpack (cgpApiBase (cfgCgp cfg))
    else "(disabled)"
  putStrLn $ "  OpenRouter: " <> if openRouterEnabled cfg
    then T.unpack (orApiBase (cfgOpenRouter cfg))
    else "(disabled)"
  putStrLn ""
  putStrLn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  putStrLn ""
  hFlush stdout


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // coeffect // manifest
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Coeffect manifest — documents resource usage for each endpoint.
--   cf. Lean4 Straylight.GradedMonad.gatewayManifest
coeffectManifest :: Value
coeffectManifest = object
  [ "endpoints" .= object
      [ "/v1/chat/completions" .= object
          [ "method"    .= ("POST" :: Text)
          , "coeffect"  .= coeffectToJson coeffectChatCompletions
          , "algebra"   .= ("Join(NetReadWrite, GpuInference)" :: Text)
          ]
      , "/v1/models" .= object
          [ "method"    .= ("GET" :: Text)
          , "coeffect"  .= coeffectToJson coeffectModels
          , "algebra"   .= ("Pure + Memory.Read" :: Text)
          ]
      , "/health" .= object
          [ "method"    .= ("GET" :: Text)
          , "coeffect"  .= coeffectToJson coeffectHealth
          , "algebra"   .= ("NetRead" :: Text)
          ]
      ]
  , "algebra" .= object
      [ "semiring" .= ("(R, ⊔, 0, ⊓, 1)" :: Text)
      , "join"     .= ("parallel composition — both resources needed" :: Text)
      , "meet"     .= ("sequential composition — max of resources" :: Text)
      , "zero"     .= ("no resource usage" :: Text)
      , "one"      .= ("unit resource usage" :: Text)
      ]
  , "proofs" .= object
      [ "join_comm"       .= ("∀ a b. a ⊔ b = b ⊔ a" :: Text)
      , "join_assoc"      .= ("∀ a b c. (a ⊔ b) ⊔ c = a ⊔ (b ⊔ c)" :: Text)
      , "join_zero_left"  .= ("∀ a. 0 ⊔ a = a" :: Text)
      , "meet_comm"       .= ("∀ a b. a ⊓ b = b ⊓ a" :: Text)
      , "meet_assoc"      .= ("∀ a b c. (a ⊓ b) ⊓ c = a ⊓ (b ⊓ c)" :: Text)
      , "absorption"      .= ("∀ a b. a ⊔ (a ⊓ b) = a" :: Text)
      ]
  , "lean4" .= ("Straylight.Coeffect, Straylight.GradedMonad" :: Text)
  ]


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // helpers
   ════════════════════════════════════════════════════════════════════════════════ -}

jsonHeaders :: [Header]
jsonHeaders = [("Content-Type", "application/json")]
