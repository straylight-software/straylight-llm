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
import Adversarial.XSSVectors qualified as XSSVectors
import Formal.ProofCorrespondence qualified as ProofCorrespondence
import Integration.ApiTests qualified as ApiTests
import Integration.LifecycleTests qualified as LifecycleTests
import Integration.OpenApiSpec qualified as OpenApiSpec
import Integration.ProofTests qualified as ProofTests
import Property.CoeffectProps qualified as CoeffectProps
import Property.GradedMonadProps qualified as GradedMonadProps
import Property.SecurityProps qualified as SecurityProps
import Property.StreamingProps qualified as StreamingProps
import Property.TypesProps qualified as TypesProps
import Test.Tasty


main :: IO ()
main = defaultMain $
    testGroup "straylight-llm"
        [ testGroup "Property Tests"
            [ TypesProps.tests
            , CoeffectProps.tests
            , GradedMonadProps.tests
            , SecurityProps.tests
            , StreamingProps.tests
            ]
        , testGroup "Integration Tests"
            [ ApiTests.tests
            , ProofTests.tests
            , LifecycleTests.tests
            , OpenApiSpec.tests
            ]
        , testGroup "Adversarial Tests"
            [ RaceConditions.tests
            , InjectionEdgeCases.tests
            , ProviderErrors.tests
            , XSSVectors.tests
            ]
        , testGroup "Formal Tests"
            [ ProofCorrespondence.tests
            ]
        ]
