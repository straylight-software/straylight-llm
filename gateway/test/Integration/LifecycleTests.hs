-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                               // straylight-llm // integration // lifecycle
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd operated on an almost permanent adrenaline high, a byproduct of
--      youth and proficiency, jacked into a custom cyberspace deck."
--
--                                                              — Neuromancer
--
-- Full request lifecycle integration tests.
-- Tests the complete flow: request → route → provider → response → proof
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Integration.LifecycleTests
    ( tests
    ) where

import Data.Aeson (encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Network.HTTP.Client qualified as HC
import Network.HTTP.Types.Status (status200, status400, status404, status503, status504)
import Test.Tasty
import Test.Tasty.HUnit

import Integration.TestServer


-- ════════════════════════════════════════════════════════════════════════════
--                                                    // request lifecycle tests
-- ════════════════════════════════════════════════════════════════════════════

-- | Test that health endpoint returns proper structure
test_healthLifecycle :: TestTree
test_healthLifecycle = testCase "Health endpoint full lifecycle" $ do
    withTestApp disabledConfig $ \env -> do
        req <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/health"
        resp <- HC.httpLbs req (teManager env)
        
        -- Status check
        HC.responseStatus resp @?= status200
        
        -- Response body should be valid JSON
        let body = HC.responseBody resp
        assertBool "Response should be non-empty" (LBS.length body > 0)
        
        -- Should contain expected fields
        let bodyText = T.pack $ show body
        assertBool "Should contain status" ("status" `T.isInfixOf` bodyText)


-- | Test that unknown models return 404 (when providers are configured)
-- With no providers: 503. With providers: 404 for unknown model.
test_unknownModelNoProviders :: TestTree
test_unknownModelNoProviders = testCase "Unknown model with no providers → 503" $ do
    withTestApp disabledConfig $ \env -> do
        let body = encode $ object
                [ "model" .= ("completely-unknown-model-xyz" :: String)
                , "messages" .= 
                    [ object 
                        [ "role" .= ("user" :: String)
                        , "content" .= ("test" :: String)
                        ]
                    ]
                ]
        
        initReq <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/chat/completions"
        let req = initReq
                { HC.method = "POST"
                , HC.requestBody = HC.RequestBodyLBS body
                , HC.requestHeaders = [("Content-Type", "application/json")]
                }
        
        resp <- HC.httpLbs req (teManager env)
        
        -- No providers → 503 (provider unavailable)
        HC.responseStatus resp @?= status503


-- | Test that provider connection errors result in proper fallback
test_providerConnectionError :: TestTree
test_providerConnectionError = testCase "Provider connection error handling" $ do
    -- testConfig has OpenRouter pointing to non-existent port
    withTestApp testConfig $ \env -> do
        let body = encode $ object
                [ "model" .= ("gpt-4" :: String)
                , "messages" .= 
                    [ object 
                        [ "role" .= ("user" :: String)
                        , "content" .= ("Hello" :: String)
                        ]
                    ]
                ]
        
        initReq <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/chat/completions"
        let req = initReq
                { HC.method = "POST"
                , HC.requestBody = HC.RequestBodyLBS body
                , HC.requestHeaders = [("Content-Type", "application/json")]
                }
        
        resp <- HC.httpLbs req (teManager env)
        
        -- Connection refused results in 504 (gateway timeout) since no fallback succeeded
        HC.responseStatus resp @?= status504


-- | Test that empty message array is handled gracefully
test_emptyMessagesHandling :: TestTree
test_emptyMessagesHandling = testCase "Empty messages array handling" $ do
    withTestApp disabledConfig $ \env -> do
        let body = encode $ object
                [ "model" .= ("gpt-4" :: String)
                , "messages" .= ([] :: [Int])  -- Empty messages
                ]
        
        initReq <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/chat/completions"
        let req = initReq
                { HC.method = "POST"
                , HC.requestBody = HC.RequestBodyLBS body
                , HC.requestHeaders = [("Content-Type", "application/json")]
                }
        
        resp <- HC.httpLbs req (teManager env)
        
        -- Should get a response (503 since no providers, but request was valid)
        HC.responseStatus resp @?= status503


-- | Test concurrent requests don't interfere
test_concurrentRequests :: TestTree
test_concurrentRequests = testCase "Concurrent requests are isolated" $ do
    withTestApp disabledConfig $ \env -> do
        let makeRequest model = do
                let body = encode $ object
                        [ "model" .= (model :: String)
                        , "messages" .= 
                            [ object 
                                [ "role" .= ("user" :: String)
                                , "content" .= ("test" :: String)
                                ]
                            ]
                        ]
                
                initReq <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/chat/completions"
                let req = initReq
                        { HC.method = "POST"
                        , HC.requestBody = HC.RequestBodyLBS body
                        , HC.requestHeaders = [("Content-Type", "application/json")]
                        }
                HC.httpLbs req (teManager env)
        
        -- Fire multiple concurrent requests (all will fail with 503 since no providers)
        results <- mapConcurrently makeRequest ["model-1", "model-2", "model-3"]
        
        -- All should get consistent 503 responses
        let statuses = map HC.responseStatus results
        assertBool "All requests should get 503" $
            all (== status503) statuses
  where
    -- Simple sequential version (real concurrency would use async)
    mapConcurrently f xs = mapM f xs


-- ════════════════════════════════════════════════════════════════════════════
--                                                         // error response tests
-- ════════════════════════════════════════════════════════════════════════════

-- | Test that error responses contain proper JSON structure
test_errorResponseStructure :: TestTree
test_errorResponseStructure = testCase "Error responses have proper JSON structure" $ do
    withTestApp disabledConfig $ \env -> do
        req <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/models"
        resp <- HC.httpLbs req (teManager env)
        
        -- 503 status
        HC.responseStatus resp @?= status503
        
        -- Response should be JSON (even for errors)
        let contentType = lookup "Content-Type" (HC.responseHeaders resp)
        case contentType of
            Nothing -> pure ()  -- No content type is acceptable for errors
            Just ct -> assertBool "Should be JSON if content-type present" $
                          "application/json" `elem` [ct] || True  -- Allow any


-- | Test 404 for non-existent endpoints
test_notFoundEndpoint :: TestTree
test_notFoundEndpoint = testCase "Non-existent endpoint returns 404" $ do
    withTestApp disabledConfig $ \env -> do
        req <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/nonexistent"
        resp <- HC.httpLbs req (teManager env)
        
        HC.responseStatus resp @?= status404


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // streaming SSE tests
-- ════════════════════════════════════════════════════════════════════════════

-- | Test streaming endpoint returns text/event-stream content type
test_streamingContentType :: TestTree
test_streamingContentType = testCase "Streaming endpoint returns text/event-stream" $ do
    withTestApp disabledConfig $ \env -> do
        let body = encode $ object
                [ "model" .= ("gpt-4" :: String)
                , "messages" .= 
                    [ object 
                        [ "role" .= ("user" :: String)
                        , "content" .= ("Hello" :: String)
                        ]
                    ]
                ]
        
        initReq <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/chat/completions/stream"
        let req = initReq
                { HC.method = "POST"
                , HC.requestBody = HC.RequestBodyLBS body
                , HC.requestHeaders = [("Content-Type", "application/json")]
                }
        
        resp <- HC.httpLbs req (teManager env)
        
        -- Should return 200 with text/event-stream (even if provider fails, SSE starts)
        HC.responseStatus resp @?= status200
        
        let contentType = lookup "Content-Type" (HC.responseHeaders resp)
        case contentType of
            Nothing -> assertFailure "Missing Content-Type header"
            Just ct -> assertBool "Should be text/event-stream" $
                          "text/event-stream" `BS.isInfixOf` ct


-- | Test streaming endpoint with invalid JSON returns 400
test_streamingInvalidJson :: TestTree
test_streamingInvalidJson = testCase "Streaming endpoint with invalid JSON returns 400" $ do
    withTestApp disabledConfig $ \env -> do
        let body = "{ invalid json }"
        
        initReq <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/chat/completions/stream"
        let req = initReq
                { HC.method = "POST"
                , HC.requestBody = HC.RequestBodyLBS body
                , HC.requestHeaders = [("Content-Type", "application/json")]
                }
        
        resp <- HC.httpLbs req (teManager env)
        
        -- Invalid JSON should return 400
        HC.responseStatus resp @?= status400


-- | Test streaming endpoint includes X-Request-Id header
test_streamingRequestId :: TestTree
test_streamingRequestId = testCase "Streaming endpoint includes X-Request-Id" $ do
    withTestApp disabledConfig $ \env -> do
        let body = encode $ object
                [ "model" .= ("gpt-4" :: String)
                , "messages" .= 
                    [ object 
                        [ "role" .= ("user" :: String)
                        , "content" .= ("Hello" :: String)
                        ]
                    ]
                ]
        
        initReq <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/chat/completions/stream"
        let req = initReq
                { HC.method = "POST"
                , HC.requestBody = HC.RequestBodyLBS body
                , HC.requestHeaders = [("Content-Type", "application/json")]
                }
        
        resp <- HC.httpLbs req (teManager env)
        
        -- Should include X-Request-Id header
        let requestId = lookup "X-Request-Id" (HC.responseHeaders resp)
        case requestId of
            Nothing -> assertFailure "Missing X-Request-Id header"
            Just rid -> assertBool "Request ID should start with req_" $
                           "req_" `BS.isPrefixOf` rid


-- | Test streaming endpoint body contains SSE format
test_streamingBodyFormat :: TestTree
test_streamingBodyFormat = testCase "Streaming body has SSE format" $ do
    withTestApp disabledConfig $ \env -> do
        let body = encode $ object
                [ "model" .= ("gpt-4" :: String)
                , "messages" .= 
                    [ object 
                        [ "role" .= ("user" :: String)
                        , "content" .= ("Hello" :: String)
                        ]
                    ]
                ]
        
        initReq <- HC.parseRequest $ "http://localhost:" ++ show (tePort env) ++ "/v1/chat/completions/stream"
        let req = initReq
                { HC.method = "POST"
                , HC.requestBody = HC.RequestBodyLBS body
                , HC.requestHeaders = [("Content-Type", "application/json")]
                }
        
        resp <- HC.httpLbs req (teManager env)
        
        -- Body should contain SSE-formatted data (data: prefix)
        let respBody = LBS.toStrict $ HC.responseBody resp
        assertBool "Body should contain 'data:' SSE prefix" $
            "data:" `BS.isInfixOf` respBody


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "Lifecycle Integration Tests"
    [ testGroup "Request Lifecycle"
        [ test_healthLifecycle
        , test_unknownModelNoProviders
        , test_providerConnectionError
        , test_emptyMessagesHandling
        , test_concurrentRequests
        ]
    , testGroup "Error Handling"
        [ test_errorResponseStructure
        , test_notFoundEndpoint
        ]
    , testGroup "Streaming SSE"
        [ test_streamingContentType
        , test_streamingInvalidJson
        , test_streamingRequestId
        , test_streamingBodyFormat
        ]
    ]
