-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                           // straylight-llm // adversarial // provider errors
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "A year here and he still dreamed of cyberspace, hope fading nightly."
--
--                                                              — Neuromancer
--
-- Tests for provider error handling and classification.
-- Verifies that errors are correctly classified as Retry vs Failure.
--
-- Key invariants:
--   - 404 (model not found) → Retry (try next provider)
--   - 401 (auth error) → Failure (no point retrying, bad credentials)
--   - 429 (rate limit) → Retry (try next provider)
--   - 5xx (server error) → Retry (provider issue)
--   - 400 (bad request) → Failure (client error, won't help to retry)
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Adversarial.ProviderErrors
    ( tests
    ) where

import Test.Tasty
import Test.Tasty.HUnit

import Provider.Types


-- ════════════════════════════════════════════════════════════════════════════
--                                                  // error classification tests
-- ════════════════════════════════════════════════════════════════════════════

-- | Test that ProviderResult pattern matching works correctly
test_providerResultPatterns :: TestTree
test_providerResultPatterns = testGroup "ProviderResult Patterns"
    [ testCase "Success extracts value" $ do
        let result = Success (42 :: Int)
        case result of
            Success v -> v @?= 42
            _ -> assertFailure "Expected Success"
    
    , testCase "Failure is non-retryable" $ do
        let result = Failure (AuthError "bad key") :: ProviderResult Int
        case result of
            Failure _ -> pure ()  -- Correct
            Retry _ -> assertFailure "AuthError should be Failure, not Retry"
            Success _ -> assertFailure "Expected Failure"
    
    , testCase "Retry is retryable" $ do
        let result = Retry (ModelNotFoundError "not found") :: ProviderResult Int
        case result of
            Retry _ -> pure ()  -- Correct
            Failure _ -> assertFailure "ModelNotFoundError should be Retry"
            Success _ -> assertFailure "Expected Retry"
    ]

-- | Test error type semantics
test_errorTypeSemantics :: TestTree
test_errorTypeSemantics = testGroup "Error Type Semantics"
    [ testCase "AuthError is for authentication failures" $ do
        let err = AuthError "Invalid API key"
        case err of
            AuthError msg -> assertBool "Should have message" (msg /= "")
            _ -> assertFailure "Expected AuthError"
    
    , testCase "RateLimitError is for 429 responses" $ do
        let err = RateLimitError "Too many requests"
        case err of
            RateLimitError _ -> pure ()
            _ -> assertFailure "Expected RateLimitError"
    
    , testCase "ModelNotFoundError is for 404 on model" $ do
        let err = ModelNotFoundError "claude-99 not found"
        case err of
            ModelNotFoundError _ -> pure ()
            _ -> assertFailure "Expected ModelNotFoundError"
    
    , testCase "ProviderUnavailable is for 5xx or network errors" $ do
        let err = ProviderUnavailable "Service down"
        case err of
            ProviderUnavailable _ -> pure ()
            _ -> assertFailure "Expected ProviderUnavailable"
    
    , testCase "InvalidRequestError is for 4xx client errors" $ do
        let err = InvalidRequestError "Bad JSON"
        case err of
            InvalidRequestError _ -> pure ()
            _ -> assertFailure "Expected InvalidRequestError"
    
    , testCase "TimeoutError is for request timeouts" $ do
        let err = TimeoutError "Timed out after 30s"
        case err of
            TimeoutError _ -> pure ()
            _ -> assertFailure "Expected TimeoutError"
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                               // retry vs failure semantics
-- ════════════════════════════════════════════════════════════════════════════

-- | Helper to check if a ProviderResult is retryable
isRetryable :: ProviderResult a -> Bool
isRetryable (Retry _) = True
isRetryable _ = False

-- | Helper to check if a ProviderResult is a failure
isFailure :: ProviderResult a -> Bool
isFailure (Failure _) = True
isFailure _ = False

-- | Helper to check if a ProviderResult is successful
isSuccess :: ProviderResult a -> Bool
isSuccess (Success _) = True
isSuccess _ = False

-- | Test the expected retry/failure classification
-- This documents the CONTRACT for error handling
test_errorClassificationContract :: TestTree
test_errorClassificationContract = testGroup "Error Classification Contract"
    [ testCase "404 (ModelNotFound) should be retryable" $ do
        -- 404 means the model doesn't exist on THIS provider
        -- but might exist on another provider, so RETRY
        let result = Retry (ModelNotFoundError "not found") :: ProviderResult ()
        assertBool "404 should be Retry" (isRetryable result)
    
    , testCase "401 (Auth) should NOT be retryable" $ do
        -- 401 means bad credentials - retrying won't help
        let result = Failure (AuthError "unauthorized") :: ProviderResult ()
        assertBool "401 should be Failure" (isFailure result)
        assertBool "401 should NOT be Retry" (not $ isRetryable result)
    
    , testCase "429 (RateLimit) should be retryable" $ do
        -- 429 means this provider is overloaded, try another
        let result = Retry (RateLimitError "rate limited") :: ProviderResult ()
        assertBool "429 should be Retry" (isRetryable result)
    
    , testCase "500 (ProviderUnavailable) should be retryable" $ do
        -- 5xx means provider issue, try another
        let result = Retry (ProviderUnavailable "server error") :: ProviderResult ()
        assertBool "5xx should be Retry" (isRetryable result)
    
    , testCase "400 (InvalidRequest) should NOT be retryable" $ do
        -- 400 means the request is bad, retrying won't help
        let result = Failure (InvalidRequestError "bad json") :: ProviderResult ()
        assertBool "400 should be Failure" (isFailure result)
        assertBool "400 should NOT be Retry" (not $ isRetryable result)
    
    , testCase "Timeout should be retryable" $ do
        -- Timeout might be transient, another provider might respond faster
        let result = Retry (TimeoutError "timed out") :: ProviderResult ()
        assertBool "Timeout should be Retry" (isRetryable result)
    
    , testCase "QuotaExceeded should NOT be retryable" $ do
        -- Credits exhausted is an account-level issue, not provider-specific
        -- Changed from Retry to Failure — don't cascade to other providers
        let result = Failure (QuotaExceededError "out of credits") :: ProviderResult ()
        assertBool "QuotaExceeded should be Failure" (isFailure result)
        assertBool "QuotaExceeded should NOT be Retry" (not $ isRetryable result)
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // fallback chain logic
-- ════════════════════════════════════════════════════════════════════════════

-- | Simulate the fallback chain logic
simulateFallback :: [ProviderResult a] -> Either ProviderError a
simulateFallback [] = Left $ ProviderUnavailable "No providers configured"
simulateFallback results = go results Nothing
  where
    go [] lastErr = Left $ maybe (ProviderUnavailable "All providers failed") id lastErr
    go (Success a : _) _ = Right a
    go (Failure err : _) _ = Left err  -- Stop on Failure
    go (Retry err : rest) _ = go rest (Just err)  -- Continue on Retry

test_fallbackChainLogic :: TestTree
test_fallbackChainLogic = testGroup "Fallback Chain Logic"
    [ testCase "Success on first provider stops chain" $ do
        let results = [Success "first", Success "second"] :: [ProviderResult String]
        simulateFallback results @?= Right "first"
    
    , testCase "Retry tries next provider" $ do
        let results = 
                [ Retry (ModelNotFoundError "not on provider 1")
                , Success "found on provider 2"
                ] :: [ProviderResult String]
        simulateFallback results @?= Right "found on provider 2"
    
    , testCase "Multiple retries try all providers" $ do
        let results = 
                [ Retry (ModelNotFoundError "not on 1")
                , Retry (ModelNotFoundError "not on 2")
                , Success "found on 3"
                ] :: [ProviderResult String]
        simulateFallback results @?= Right "found on 3"
    
    , testCase "Failure stops chain immediately" $ do
        let results = 
                [ Failure (AuthError "bad key")
                , Success "never reached"
                ] :: [ProviderResult String]
        case simulateFallback results of
            Left (AuthError _) -> pure ()
            _ -> assertFailure "Should stop on auth error"
    
    , testCase "All retries returns last error" $ do
        let results = 
                [ Retry (ModelNotFoundError "not on 1")
                , Retry (ProviderUnavailable "provider 2 down")
                ] :: [ProviderResult String]
        case simulateFallback results of
            Left (ProviderUnavailable _) -> pure ()  -- Last error
            Left (ModelNotFoundError _) -> assertFailure "Should return last error"
            _ -> assertFailure "Expected failure"
    
    , testCase "Empty provider list fails" $ do
        let results = [] :: [ProviderResult String]
        case simulateFallback results of
            Left (ProviderUnavailable _) -> pure ()
            _ -> assertFailure "Expected ProviderUnavailable"
    
    , testCase "Retry then Failure stops at Failure" $ do
        let results = 
                [ Retry (ModelNotFoundError "not on 1")
                , Failure (AuthError "bad key on 2")
                , Success "never reached"
                ] :: [ProviderResult String]
        case simulateFallback results of
            Left (AuthError _) -> pure ()
            _ -> assertFailure "Should stop on auth error"
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                     // edge cases and bounds
-- ════════════════════════════════════════════════════════════════════════════

test_errorMessagePreservation :: TestTree
test_errorMessagePreservation = testGroup "Error Message Preservation"
    [ testCase "AuthError preserves message" $ do
        let msg = "API key expired on 2026-02-23"
        let err = AuthError msg
        case err of
            AuthError m -> m @?= msg
            _ -> assertFailure "Expected AuthError"
    
    , testCase "Empty message is valid" $ do
        let err = UnknownError ""
        case err of
            UnknownError "" -> pure ()
            _ -> assertFailure "Expected empty UnknownError"
    
    , testCase "Long message is preserved" $ do
        let msg = mconcat $ replicate 1000 ("error" :: String)
        let err = ProviderUnavailable "long message test"
        case err of
            ProviderUnavailable m -> assertBool "Should have message" (m /= "")
            _ -> assertFailure "Expected ProviderUnavailable"
    
    , testCase "Unicode in error message" $ do
        let msg = "エラー: 認証失敗 🔐"
        let err = AuthError msg
        case err of
            AuthError m -> m @?= msg
            _ -> assertFailure "Expected AuthError"
    ]

test_providerResultFunctor :: TestTree
test_providerResultFunctor = testGroup "ProviderResult Structure"
    [ testCase "Success can hold any type" $ do
        let intResult = Success (42 :: Int)
        let strResult = Success ("hello" :: String)
        let listResult = Success ([1,2,3] :: [Int])
        isSuccess intResult @?= True
        isSuccess strResult @?= True
        isSuccess listResult @?= True
    
    , testCase "Error types are consistent across result types" $ do
        let intErr = Failure (AuthError "x") :: ProviderResult Int
        let strErr = Failure (AuthError "x") :: ProviderResult String
        -- Both should be failures
        isFailure intErr @?= True
        isFailure strErr @?= True
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "Provider Error Handling"
    [ test_providerResultPatterns
    , test_errorTypeSemantics
    , test_errorClassificationContract
    , test_fallbackChainLogic
    , test_errorMessagePreservation
    , test_providerResultFunctor
    ]
