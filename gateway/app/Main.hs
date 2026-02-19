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

import Network.HTTP.Types (methodOptions, status200)
import Network.Wai (Middleware, mapResponseHeaders, requestMethod, responseLBS)
import Network.Wai.Handler.Warp (run)
import Servant (serve)
import System.IO (BufferMode (..), hSetBuffering, stdout)

import Data.Text qualified as T
import Data.Text.IO qualified as TIO

import Api (api)
import Config (Config (..), loadConfig)
import Handlers (server)
import Router (makeRouter)


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
        [ ("Access-Control-Allow-Origin", "*")
        , ("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        , ("Access-Control-Allow-Headers", "Authorization, Content-Type")
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
    logProviderStatus "Venice AI" (cfgVenice config)
    logProviderStatus "Vertex AI" (cfgVertex config)
    logProviderStatus "Baseten" (cfgBaseten config)
    logProviderStatus "OpenRouter" (cfgOpenRouter config)
    TIO.putStrLn ""

    -- Create router with provider chain
    router <- makeRouter config

    -- Start server
    let port = cfgPort config
    TIO.putStrLn $ "listening on port " <> T.pack (show port)
    TIO.putStrLn ""

    let app = enableCors $ serve api (server router)
    run port app

-- | Log provider configuration status
logProviderStatus :: T.Text -> Config.ProviderConfig -> IO ()
logProviderStatus name cfg = do
    let status = if Config.pcEnabled cfg && Config.pcApiKey cfg /= Nothing
                 then "[enabled]"
                 else "[disabled]"
    TIO.putStrLn $ "  " <> name <> ": " <> status

-- Import for ProviderConfig access
import Config (ProviderConfig (..))
