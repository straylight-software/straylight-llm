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
import Config
  ( Config
      ( cfgAnthropic,
        cfgBaseten,
        cfgCacheConfig,
        cfgOpenRouter,
        cfgPort,
        cfgTriton,
        cfgVenice,
        cfgVertex
      ),
    ProviderConfig (pcApiKey, pcEnabled),
    ResponseCacheConfig (rccEnabled, rccMaxSize, rccTtlSeconds),
    loadConfig,
  )
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Evring.Wai qualified as Evring
import Handlers (server)
import Network.HTTP.Types (methodOptions, status200)
import Network.Wai (Middleware, mapResponseHeaders, requestMethod, responseLBS)
import Network.Wai.Handler.Warp qualified as Warp
import Observability.Logging
  ( LogConfig (lcLevel),
    LogLevel (LogDebug, LogError, LogInfo, LogWarn),
    initLogger,
    loadLogConfig,
    loggingMiddleware,
  )
import Observability.Tracing
  ( TracingConfig (tcEnabled, tcOtlpEndpoint),
    initTracer,
    loadTracingConfig,
    tracingMiddleware,
  )
import Resilience.RateLimiter
  ( RateLimitConfig (rlcEnabled),
    loadRateLimitConfig,
    newRateLimiter,
    rateLimitMiddleware,
  )
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

  -- Initialize structured logging
  logConfig <- loadLogConfig
  logger <- initLogger logConfig

  -- Initialize OpenTelemetry tracing
  tracingConfig <- loadTracingConfig
  tracer <- initTracer tracingConfig

  -- Initialize rate limiter
  rateLimitConfig <- loadRateLimitConfig
  rateLimiter <- newRateLimiter rateLimitConfig

  -- Log observability status
  TIO.putStrLn $ "  Logging: [" <> logLevelText (lcLevel logConfig) <> "] (set LOG_LEVEL to change)"
  if tcEnabled tracingConfig
    then TIO.putStrLn $ "  OpenTelemetry: [enabled] -> " <> tcOtlpEndpoint tracingConfig
    else TIO.putStrLn "  OpenTelemetry: [disabled] (set OTEL_ENABLED=true to enable)"
  if rlcEnabled rateLimitConfig
    then TIO.putStrLn "  Rate Limiting: [enabled] (set RATE_LIMIT_RPM/RATE_LIMIT_BURST to configure)"
    else TIO.putStrLn "  Rate Limiting: [disabled] (set RATE_LIMIT_ENABLED=true to enable)"
  let cacheConf = cfgCacheConfig config
  if rccEnabled cacheConf
    then
      TIO.putStrLn $
        "  Response Cache: [enabled] max="
          <> T.pack (show (rccMaxSize cacheConf))
          <> " ttl="
          <> T.pack (show (rccTtlSeconds cacheConf))
          <> "s"
    else TIO.putStrLn "  Response Cache: [disabled] (set CACHE_ENABLED=true to enable)"
  TIO.putStrLn ""

  -- Check backend selection environment variables
  -- USE_URING=1 enables io_uring (5.1x throughput, 63x better tail latency)
  -- USE_WARP=1 forces Warp (for WSL2 or systems without io_uring)
  -- Default: Warp (safe default until io_uring is validated in your environment)
  useUring <- lookupEnv "USE_URING"
  useWarp <- lookupEnv "USE_WARP"

  -- Start server
  let port = cfgPort config
      -- Middleware stack: CORS -> RateLimit -> Logging -> Tracing -> Servant
      app =
        enableCors $
          rateLimitMiddleware rateLimiter $
            loggingMiddleware logger $
              tracingMiddleware tracer $
                serve api (server router)

  -- Log server backend info
  TIO.putStrLn "════════════════════════════════════════════════════════════════════════════════"
  TIO.putStrLn "                                                           // server //"
  TIO.putStrLn "════════════════════════════════════════════════════════════════════════════════"
  TIO.putStrLn ""

  case (useUring, useWarp) of
    (Just _, _) -> do
      -- io_uring backend (5.1x throughput, 63x better tail latency)
      TIO.putStrLn "  backend: evring-wai (io_uring)"
      TIO.putStrLn $ "  listening on port " <> T.pack (show port)
      TIO.putStrLn ""
      Evring.runEvring port app
    (_, Just _) -> do
      -- Warp fallback (for WSL2 or systems without io_uring)
      TIO.putStrLn "  backend: Warp (USE_WARP=1)"
      TIO.putStrLn $ "  listening on port " <> T.pack (show port)
      TIO.putStrLn ""
      Warp.run port app
    (Nothing, Nothing) -> do
      -- Default: Warp (safe default)
      TIO.putStrLn "  backend: Warp (default, set USE_URING=1 for io_uring)"
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

-- | Convert log level to display text
logLevelText :: LogLevel -> T.Text
logLevelText LogDebug = "debug"
logLevelText LogInfo = "info"
logLevelText LogWarn = "warn"
logLevelText LogError = "error"
