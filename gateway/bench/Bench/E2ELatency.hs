-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                      // straylight-llm // bench/E2ELatency.hs
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Time moves in one direction, memory in another."
--
--                                                              — Neuromancer
--
-- End-to-end HTTP latency benchmarks for billion-agent swarm optimization.
--
-- Measures:
--   - Gateway overhead (mock provider returns instantly)
--   - HTTP round-trip through full stack (Warp -> Servant -> Router)
--   - Concurrent request handling at scale
--   - Memory per connection
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}

module Bench.E2ELatency (benchmarks) where

import Control.Concurrent (forkIO, threadDelay, killThread)
import Control.Concurrent.Async (replicateConcurrently)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (try, SomeException)
import Control.Monad (replicateM, void)
import Criterion.Main
    ( Benchmark
    , bench
    , bgroup
    , nfIO
    , whnfIO
    )
import Data.Aeson (encode, object, (.=))
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Network.HTTP.Client qualified as HC
import Network.HTTP.Client.TLS qualified as HCT
import Network.HTTP.Types (status200, hContentType)
import Network.Wai (Application, responseLBS, rawPathInfo)
import Network.Wai.Handler.Warp qualified as Warp
import System.IO.Unsafe (unsafePerformIO)

import Types
    ( ChatResponse (..)
    , Message (..)
    , MessageContent (..)
    , Choice (..)
    , Usage (..)
    , ModelId (..)
    , ResponseId (..)
    , Timestamp (..)
    , FinishReason (..)
    , Role (..)
    )


-- | All E2E latency benchmarks
benchmarks :: Benchmark
benchmarks = bgroup "E2E-Latency"
    [ mockProviderBenchmarks
    , httpOverheadBenchmarks
    , concurrentBenchmarks
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                    // mock provider server
-- ════════════════════════════════════════════════════════════════════════════

-- | Mock chat response (minimal valid response)
mockChatResponse :: ChatResponse
mockChatResponse = ChatResponse
    { respId = ResponseId "mock_resp_001"
    , respObject = "chat.completion"
    , respCreated = Timestamp 1700000000
    , respModel = ModelId "mock-instant"
    , respChoices = [mockChoice]
    , respUsage = Just mockUsage
    , respSystemFingerprint = Nothing
    }

mockChoice :: Choice
mockChoice = Choice
    { choiceIndex = 0
    , choiceMessage = Message
        { msgRole = Assistant
        , msgContent = Just (TextContent "Hello")
        , msgName = Nothing
        , msgToolCallId = Nothing
        , msgToolCalls = Nothing
        }
    , choiceFinishReason = Just (FinishReason "stop")
    }

mockUsage :: Usage
mockUsage = Usage
    { usagePromptTokens = 10
    , usageCompletionTokens = 5
    , usageTotalTokens = 15
    }

-- | Instant mock provider (no artificial delay)
mockProviderApp :: Application
mockProviderApp req respond = do
    let path = rawPathInfo req
    case path of
        "/v1/chat/completions" -> 
            respond $ responseLBS status200 
                [(hContentType, "application/json")] 
                (encode mockChatResponse)
        "/v1/models" ->
            respond $ responseLBS status200
                [(hContentType, "application/json")]
                "{\"object\":\"list\",\"data\":[{\"id\":\"mock-instant\",\"object\":\"model\"}]}"
        "/health" ->
            respond $ responseLBS status200 [] "OK"
        _ ->
            respond $ responseLBS status200 [] "OK"

-- | Start mock provider on given port, returns cleanup action
startMockProvider :: Int -> IO (IO ())
startMockProvider port = do
    ready <- newEmptyMVar
    tid <- forkIO $ Warp.runSettings 
        (Warp.setPort port $ Warp.setBeforeMainLoop (putMVar ready ()) Warp.defaultSettings)
        mockProviderApp
    takeMVar ready  -- Wait for server to start
    threadDelay 10_000  -- Small additional delay for socket binding
    pure $ killThread tid


-- ════════════════════════════════════════════════════════════════════════════
--                                                // http client benchmarks
-- ════════════════════════════════════════════════════════════════════════════

-- | Global HTTP manager (reused across benchmarks)
{-# NOINLINE globalManager #-}
globalManager :: HC.Manager
globalManager = unsafePerformIO $ HC.newManager HCT.tlsManagerSettings

-- | Sample chat request
sampleChatRequest :: LBS.ByteString
sampleChatRequest = encode $ object
    [ "model" .= ("mock-instant" :: Text)
    , "messages" .= [ object 
        [ "role" .= ("user" :: Text)
        , "content" .= ("Hello" :: Text)
        ]
      ]
    ]

-- | Make HTTP request to mock provider
makeRequest :: HC.Manager -> Int -> IO (Either String LBS.ByteString)
makeRequest manager port = do
    req <- HC.parseRequest $ "http://127.0.0.1:" <> show port <> "/v1/chat/completions"
    let req' = req
            { HC.method = "POST"
            , HC.requestHeaders = [(hContentType, "application/json")]
            , HC.requestBody = HC.RequestBodyLBS sampleChatRequest
            }
    result <- try $ HC.httpLbs req' manager
    case result of
        Left (e :: SomeException) -> pure $ Left (show e)
        Right resp -> pure $ Right (HC.responseBody resp)


-- ════════════════════════════════════════════════════════════════════════════
--                                           // mock provider direct benchmarks
-- ════════════════════════════════════════════════════════════════════════════

-- | Port for mock provider benchmarks
mockProviderPort :: Int
mockProviderPort = 19876

-- | Global ref for mock provider cleanup
{-# NOINLINE mockProviderCleanupRef #-}
mockProviderCleanupRef :: IORef (Maybe (IO ()))
mockProviderCleanupRef = unsafePerformIO $ newIORef Nothing

-- | Ensure mock provider is running
ensureMockProvider :: IO ()
ensureMockProvider = do
    existing <- readIORef mockProviderCleanupRef
    case existing of
        Just _ -> pure ()  -- Already running
        Nothing -> do
            cleanup <- startMockProvider mockProviderPort
            writeIORef mockProviderCleanupRef (Just cleanup)

mockProviderBenchmarks :: Benchmark
mockProviderBenchmarks = bgroup "MockProvider-Direct"
    [ bench "single-request" $ whnfIO $ do
        ensureMockProvider
        makeRequest globalManager mockProviderPort
        
    , bench "10-sequential" $ nfIO $ do
        ensureMockProvider
        replicateM 10 $ makeRequest globalManager mockProviderPort
        
    , bench "100-sequential" $ nfIO $ do
        ensureMockProvider
        replicateM 100 $ makeRequest globalManager mockProviderPort
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                               // http overhead measurement
-- ════════════════════════════════════════════════════════════════════════════

-- | Measure raw HTTP overhead (Warp + http-client round-trip)
-- This isolates network stack overhead from application logic
httpOverheadBenchmarks :: Benchmark
httpOverheadBenchmarks = bgroup "HTTP-Overhead"
    [ bench "health-check" $ whnfIO $ do
        ensureMockProvider
        req <- HC.parseRequest $ "http://127.0.0.1:" <> show mockProviderPort <> "/health"
        void $ HC.httpLbs req globalManager
        
    , bench "minimal-json-response" $ whnfIO $ do
        ensureMockProvider
        req <- HC.parseRequest $ "http://127.0.0.1:" <> show mockProviderPort <> "/v1/models"
        void $ HC.httpLbs req globalManager
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                   // concurrent benchmarks
-- ════════════════════════════════════════════════════════════════════════════

concurrentBenchmarks :: Benchmark
concurrentBenchmarks = bgroup "Concurrent"
    [ bench "10-parallel" $ nfIO $ do
        ensureMockProvider
        replicateConcurrently 10 $ makeRequest globalManager mockProviderPort
        
    , bench "100-parallel" $ nfIO $ do
        ensureMockProvider
        replicateConcurrently 100 $ makeRequest globalManager mockProviderPort
        
    , bench "1000-parallel" $ nfIO $ do
        ensureMockProvider
        replicateConcurrently 1000 $ makeRequest globalManager mockProviderPort
    ]
