-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                    // straylight-llm // integration // proof
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd operated on an almost permanent adrenaline high, a byproduct
--      of youth and proficiency, jacked into a custom cyberspace deck."
--
--                                                              — Neuromancer
--
-- Integration tests for the discharge proof API.
-- Tests proof generation and retrieval via /v1/proof/:requestId endpoint.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Integration.ProofTests
    ( tests
    ) where

import Network.HTTP.Client qualified as HC
import Network.HTTP.Types.Status (status404)
import Test.Tasty
import Test.Tasty.HUnit

import Integration.TestServer


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // proof tests
-- ════════════════════════════════════════════════════════════════════════════

test_proofNotFound :: TestTree
test_proofNotFound = testCase "GET /v1/proof/:requestId returns 404 for unknown request" $ do
    withTestApp disabledConfig $ \env -> do
        req <- HC.parseRequest $ 
            "http://localhost:" ++ show (tePort env) ++ "/v1/proof/unknown-request-id"
        resp <- HC.httpLbs req (teManager env)
        
        -- Unknown request ID should return 404
        HC.responseStatus resp @?= status404


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "Proof Integration Tests"
    [ testGroup "Proof Endpoint"
        [ test_proofNotFound
        ]
    ]
