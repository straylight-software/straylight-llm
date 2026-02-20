-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                               // straylight-llm // test main
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The matrix has its roots in primitive arcade games."
--
--                                                              — Neuromancer
--
-- Test runner for straylight-llm property tests.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

module Main where

import Integration.ApiTests qualified as ApiTests
import Integration.ProofTests qualified as ProofTests
import Property.CoeffectProps qualified as CoeffectProps
import Property.TypesProps qualified as TypesProps
import Test.Tasty


main :: IO ()
main = defaultMain $
    testGroup "straylight-llm"
        [ testGroup "Property Tests"
            [ TypesProps.tests
            , CoeffectProps.tests
            ]
        , testGroup "Integration Tests"
            [ ApiTests.tests
            , ProofTests.tests
            ]
        ]
