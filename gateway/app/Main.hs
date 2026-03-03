-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                              // straylight-llm // main
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The sky above the port was the color of television, tuned to a dead
--      channel."
--
--                                                              — Neuromancer
--
-- Entry point for straylight-llm, a LiteLLM-style OpenAI-compatible proxy.
-- Routes requests through provider fallback chain:
--
--     Venice AI -> Vertex AI (GCP) -> Baseten -> OpenRouter
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Api (api)
import Config (Config (..), ProviderConfig (..), loadConfig)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Evring.Wai qualified as Evring
import Handlers (server)
import Network.HTTP.Types (methodOptions, status200)
import Network.Wai (Middleware, mapResponseHeaders, requestMethod, responseLBS)
import Network.Wai.Handler.Warp qualified as Warp
import Router (makeRouter)
import Servant (serve)
import System.Environment (lookupEnv)
import System.IO (BufferMode (..), hSetBuffering, stdout)

-- ════════════════════════════════════════════════════════════════════════════
--                                                              // middleware
-- ════════════════════════════════════════════════════════════════════════════

-- | CORS middleware for cross-origin requests
enableCors :: Middleware
enableCors app req callback
  | requestMethod req == methodOptions =
      callback $ responseLBS status200 corsHeaders ""
  | otherwise =
      app req $ \response ->
        callback $ mapResponseHeaders (<> corsHeaders) response
  where
    corsHeaders =
      [ ("Access-Control-Allow-Origin", "*"),
        ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
        ("Access-Control-Allow-Headers", "Authorization, Content-Type")
      ]

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // main
-- ════════════════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering

  -- Banner
  TIO.putStrLn ""
  TIO.putStrLn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  TIO.putStrLn "                                                   // straylight-llm //"
  TIO.putStrLn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  TIO.putStrLn ""
  TIO.putStrLn "    \"The sky above the port was the color of television,"
  TIO.putStrLn "     tuned to a dead channel.\""
  TIO.putStrLn ""
  TIO.putStrLn "                                                             — Neuromancer"
  TIO.putStrLn ""

  -- Load configuration from environment
  config <- loadConfig

  -- Log provider status
  TIO.putStrLn "════════════════════════════════════════════════════════════════════════════════"
  TIO.putStrLn "                                                         // providers //"
  TIO.putStrLn "════════════════════════════════════════════════════════════════════════════════"
  TIO.putStrLn ""
  logProviderStatus "Triton (local)" (cfgTriton config)
  logProviderStatus "Venice AI" (cfgVenice config)
  logProviderStatus "Vertex AI" (cfgVertex config)
  logProviderStatus "Baseten" (cfgBaseten config)
  logProviderStatus "OpenRouter" (cfgOpenRouter config)
  logProviderStatus "Anthropic" (cfgAnthropic config)
  TIO.putStrLn ""

  -- Create router with provider chain
  router <- makeRouter config

  -- Check backend selection environment variables
  -- USE_URING=1 enables io_uring single-core (CPS event loop)
  -- USE_URING_MC=1 enables io_uring multi-core (SO_REUSEPORT, one ring per core)
  -- USE_WARP=1 forces Warp (for WSL2 or systems without io_uring)
  -- Default: Warp (safe default until io_uring is validated in your environment)
  useUring <- lookupEnv "USE_URING"
  useUringMC <- lookupEnv "USE_URING_MC"
  useWarp <- lookupEnv "USE_WARP"

  -- Start server
  let port = cfgPort config
      app = enableCors $ serve api (server router)

  -- Log server backend info
  TIO.putStrLn "════════════════════════════════════════════════════════════════════════════════"
  TIO.putStrLn "                                                           // server //"
  TIO.putStrLn "════════════════════════════════════════════════════════════════════════════════"
  TIO.putStrLn ""

  case (useUringMC, useUring, useWarp) of
    (Just _, _, _) -> do
      -- io_uring multi-core backend (maximum throughput)
      TIO.putStrLn "  backend: evring-wai (io_uring, multi-core)"
      TIO.putStrLn $ "  listening on port " <> T.pack (show port)
      TIO.putStrLn ""
      Evring.runEvringMultiCore port app
    (_, Just _, _) -> do
      -- io_uring single-core backend
      TIO.putStrLn "  backend: evring-wai (io_uring, single-core)"
      TIO.putStrLn $ "  listening on port " <> T.pack (show port)
      TIO.putStrLn ""
      Evring.runEvring port app
    (_, _, Just _) -> do
      -- Warp fallback (for WSL2 or systems without io_uring)
      TIO.putStrLn "  backend: Warp (USE_WARP=1)"
      TIO.putStrLn $ "  listening on port " <> T.pack (show port)
      TIO.putStrLn ""
      Warp.run port app
    (Nothing, Nothing, Nothing) -> do
      -- Default: Warp (safe default)
      TIO.putStrLn "  backend: Warp (default, set USE_URING=1 or USE_URING_MC=1 for io_uring)"
      TIO.putStrLn $ "  listening on port " <> T.pack (show port)
      TIO.putStrLn ""
      Warp.run port app

-- | Log provider configuration status
logProviderStatus :: T.Text -> ProviderConfig -> IO ()
logProviderStatus name cfg = do
  let status =
        if pcEnabled cfg && pcApiKey cfg /= Nothing
          then "[enabled]"
          else "[disabled]"
  TIO.putStrLn $ "  " <> name <> ": " <> status
