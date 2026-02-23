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

import Adversarial.InjectionEdgeCases qualified as InjectionEdgeCases
import Adversarial.ProviderErrors qualified as ProviderErrors
import Adversarial.RaceConditions qualified as RaceConditions
import Integration.ApiTests qualified as ApiTests
import Integration.ProofTests qualified as ProofTests
import Property.CoeffectProps qualified as CoeffectProps
import Property.GradedMonadProps qualified as GradedMonadProps
import Property.TypesProps qualified as TypesProps
import Test.Tasty


main :: IO ()
main = defaultMain $
    testGroup "straylight-llm"
        [ testGroup "Property Tests"
            [ TypesProps.tests
            , CoeffectProps.tests
            , GradedMonadProps.tests
            ]
        , testGroup "Integration Tests"
            [ ApiTests.tests
            , ProofTests.tests
            ]
        , testGroup "Adversarial Tests"
            [ RaceConditions.tests
            , InjectionEdgeCases.tests
            , ProviderErrors.tests
            ]
        ]
