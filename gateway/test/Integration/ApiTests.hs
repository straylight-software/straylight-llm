-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                    // straylight-llm // integration // api
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "A year here and he still dreamed of cyberspace, hope fading nightly."
--
--                                                              — Neuromancer
--
-- Integration tests for the gateway API endpoints.
-- Tests health, models, chat completions, and embeddings endpoints
-- against a real (in-process) Warp server.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}

module Integration.ApiTests
  ( tests,
  )
where

import Api (HealthResponse (..))
import Data.Aeson (decode, encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Integration.TestServer
import Network.HTTP.Client qualified as HC
import Network.HTTP.Types.Status (status200, status503)
import Test.Tasty
import Test.Tasty.HUnit

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // health tests
-- ════════════════════════════════════════════════════════════════════════════

test_healthEndpoint :: TestTree
test_healthEndpoint = testCase "GET /health returns 200 OK" $ do
  withTestApp disabledConfig $ \env -> do
    req <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/health"
    resp <- HC.httpLbs req (teManager env)

    -- Check status code
    HC.responseStatus resp @?= status200

    -- Check response body
    let mBody = decode (HC.responseBody resp) :: Maybe HealthResponse
    case mBody of
      Nothing -> assertFailure "Failed to decode health response"
      Just health -> do
        hrStatus health @?= "ok"
        hrVersion health @?= "0.1.0"

test_healthContentType :: TestTree
test_healthContentType = testCase "GET /health returns application/json" $ do
  withTestApp disabledConfig $ \env -> do
    req <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/health"
    resp <- HC.httpLbs req (teManager env)

    -- Check content type header
    let headers = HC.responseHeaders resp
        contentType = lookup "Content-Type" headers
    case contentType of
      Nothing -> assertFailure "Missing Content-Type header"
      Just ct ->
        assertBool
          "Content-Type should be application/json"
          (BS.isPrefixOf "application/json" ct)

-- ════════════════════════════════════════════════════════════════════════════
--                                                       // prometheus tests
-- ════════════════════════════════════════════════════════════════════════════

test_prometheusEndpoint :: TestTree
test_prometheusEndpoint = testCase "GET /metrics returns Prometheus text format" $ do
  withTestApp disabledConfig $ \env -> do
    req <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/metrics"
    resp <- HC.httpLbs req (teManager env)

    -- Check status code
    HC.responseStatus resp @?= status200

    -- Check content type header (should be text/plain for Prometheus)
    let headers = HC.responseHeaders resp
        contentType = lookup "Content-Type" headers
    case contentType of
      Nothing -> assertFailure "Missing Content-Type header"
      Just ct ->
        assertBool
          "Content-Type should be text/plain"
          (BS.isPrefixOf "text/plain" ct)

    -- Check response body contains expected Prometheus metrics
    let body = TE.decodeUtf8 $ LBS.toStrict $ HC.responseBody resp
    assertBool "Should contain straylight_requests_total" $
      T.isInfixOf "straylight_requests_total" body
    assertBool "Should contain # TYPE line" $
      T.isInfixOf "# TYPE straylight_requests_total counter" body
    assertBool "Should contain # HELP line" $
      T.isInfixOf "# HELP straylight_requests_total" body

test_prometheusNoAuth :: TestTree
test_prometheusNoAuth = testCase "GET /metrics requires no authentication" $ do
  withTestApp disabledConfig $ \env -> do
    -- No auth header - should still succeed
    req <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/metrics"
    resp <- HC.httpLbs req (teManager env)

    -- Should get 200, not 401
    HC.responseStatus resp @?= status200

-- ════════════════════════════════════════════════════════════════════════════
--                                                            // models tests
-- ════════════════════════════════════════════════════════════════════════════

test_modelsNoProviders :: TestTree
test_modelsNoProviders = testCase "GET /v1/models with no providers returns 503" $ do
  withTestApp disabledConfig $ \env -> do
    req <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/models"
    -- Expect 503 since no providers are enabled
    resp <- HC.httpLbs req (teManager env)

    -- With all providers disabled, should get 503 Provider Unavailable
    HC.responseStatus resp @?= status503

-- ════════════════════════════════════════════════════════════════════════════
--                                                       // completions tests
-- ════════════════════════════════════════════════════════════════════════════

test_chatNoProviders :: TestTree
test_chatNoProviders = testCase "POST /v1/chat/completions with no providers returns 503" $ do
  withTestApp disabledConfig $ \env -> do
    let body =
          encode $
            object
              [ "model" .= ("gpt-4" :: String),
                "messages"
                  .= [ object
                         [ "role" .= ("user" :: String),
                           "content" .= ("Hello" :: String)
                         ]
                     ]
              ]

    initReq <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/chat/completions"
    let req =
          initReq
            { HC.method = "POST",
              HC.requestBody = HC.RequestBodyLBS body,
              HC.requestHeaders = [("Content-Type", "application/json")]
            }

    resp <- HC.httpLbs req (teManager env)

    -- With all providers disabled, should get 503 Provider Unavailable
    HC.responseStatus resp @?= status503

-- ════════════════════════════════════════════════════════════════════════════
--                                                          // embeddings tests
-- ════════════════════════════════════════════════════════════════════════════

test_embeddingsNoProviders :: TestTree
test_embeddingsNoProviders = testCase "POST /v1/embeddings with no providers returns 503" $ do
  withTestApp disabledConfig $ \env -> do
    let body =
          encode $
            object
              [ "model" .= ("text-embedding-ada-002" :: String),
                "input" .= ("Hello, world!" :: String)
              ]

    initReq <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/embeddings"
    let req =
          initReq
            { HC.method = "POST",
              HC.requestBody = HC.RequestBodyLBS body,
              HC.requestHeaders = [("Content-Type", "application/json")]
            }

    resp <- HC.httpLbs req (teManager env)

    -- With all providers disabled, should get 503 Provider Unavailable
    HC.responseStatus resp @?= status503

-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests =
  testGroup
    "API Integration Tests"
    [ testGroup
        "Health Endpoint"
        [ test_healthEndpoint,
          test_healthContentType
        ],
      testGroup
        "Prometheus Metrics"
        [ test_prometheusEndpoint,
          test_prometheusNoAuth
        ],
      testGroup
        "Models Endpoint"
        [ test_modelsNoProviders
        ],
      testGroup
        "Chat Completions"
        [ test_chatNoProviders
        ],
      testGroup
        "Embeddings"
        [ test_embeddingsNoProviders
        ]
    ]
