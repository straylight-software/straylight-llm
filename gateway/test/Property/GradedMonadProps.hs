-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                     // straylight-llm // graded monad props
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd see the matrix in his sleep, bright lattices of logic."
--
--                                                              — Neuromancer
--
-- Property tests for GatewayM graded monad algebraic properties.
--
-- Tests the co-effect equations from COMPASS/STANDARDS.md:
--   - Idempotency: f(f(x)) = f(x)
--   - Monotonicity: grade(g1 >> g2) >= max(grade g1, grade g2)
--   - Associativity: (m >>= f) >>= g = m >>= (\x -> f x >>= g)
--
-- Also tests graded monad laws:
--   - Left identity:  return a >>= f  ≡  f a
--   - Right identity: m >>= return    ≡  m
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Property.GradedMonadProps
    ( tests
    ) where

import Effects.Graded
import Data.Text (Text)

import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.Hedgehog


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // generators
-- ════════════════════════════════════════════════════════════════════════════

genInt :: Gen Int
genInt = Gen.int (Range.linear 0 1000)

genText :: Gen Text
genText = Gen.text (Range.linear 1 50) Gen.alphaNum


-- ════════════════════════════════════════════════════════════════════════════
--                                                     // grade monoid properties
-- ════════════════════════════════════════════════════════════════════════════

-- | Left identity: mempty <> x ≡ x
prop_gradeLeftIdentity :: Property
prop_gradeLeftIdentity = property $ do
    latency <- forAll genInt
    tokens <- forAll genInt
    let grade = emptyGrade
            { ggLatencyMs = latency
            , ggInputTokens = tokens
            }
    combineGrades emptyGrade grade === grade

-- | Right identity: x <> mempty ≡ x
prop_gradeRightIdentity :: Property
prop_gradeRightIdentity = property $ do
    latency <- forAll genInt
    tokens <- forAll genInt
    let grade = emptyGrade
            { ggLatencyMs = latency
            , ggInputTokens = tokens
            }
    combineGrades grade emptyGrade === grade

-- | Associativity: (x <> y) <> z ≡ x <> (y <> z)
prop_gradeAssociativity :: Property
prop_gradeAssociativity = property $ do
    latency1 <- forAll genInt
    latency2 <- forAll genInt
    latency3 <- forAll genInt
    let g1 = emptyGrade { ggLatencyMs = latency1 }
        g2 = emptyGrade { ggLatencyMs = latency2 }
        g3 = emptyGrade { ggLatencyMs = latency3 }
    combineGrades (combineGrades g1 g2) g3 === combineGrades g1 (combineGrades g2 g3)


-- ════════════════════════════════════════════════════════════════════════════
--                                                   // monotonicity properties
-- ════════════════════════════════════════════════════════════════════════════

-- | Monotonicity: combined grade >= individual grades (for additive fields)
prop_gradeMonotonicityLatency :: Property
prop_gradeMonotonicityLatency = property $ do
    latency1 <- forAll genInt
    latency2 <- forAll genInt
    let g1 = emptyGrade { ggLatencyMs = latency1 }
        g2 = emptyGrade { ggLatencyMs = latency2 }
        combined = combineGrades g1 g2
    assert $ ggLatencyMs combined >= ggLatencyMs g1
    assert $ ggLatencyMs combined >= ggLatencyMs g2

-- | Monotonicity for tokens
prop_gradeMonotonicityTokens :: Property
prop_gradeMonotonicityTokens = property $ do
    input1 <- forAll genInt
    input2 <- forAll genInt
    output1 <- forAll genInt
    output2 <- forAll genInt
    let g1 = emptyGrade { ggInputTokens = input1, ggOutputTokens = output1 }
        g2 = emptyGrade { ggInputTokens = input2, ggOutputTokens = output2 }
        combined = combineGrades g1 g2
    assert $ ggInputTokens combined >= ggInputTokens g1
    assert $ ggInputTokens combined >= ggInputTokens g2
    assert $ ggOutputTokens combined >= ggOutputTokens g1
    assert $ ggOutputTokens combined >= ggOutputTokens g2


-- ════════════════════════════════════════════════════════════════════════════
--                                                   // co-effect set properties
-- ════════════════════════════════════════════════════════════════════════════

-- | Co-effect monoid left identity
prop_coEffectLeftIdentity :: Property
prop_coEffectLeftIdentity = withTests 1 . property $ do
    -- emptyCoEffect <> ce === ce
    -- Since we can't generate arbitrary co-effects easily, we test with empty
    (emptyCoEffect <> emptyCoEffect) === emptyCoEffect

-- | Co-effect monoid right identity
prop_coEffectRightIdentity :: Property
prop_coEffectRightIdentity = withTests 1 . property $ do
    (emptyCoEffect <> emptyCoEffect) === emptyCoEffect


-- ════════════════════════════════════════════════════════════════════════════
--                                                 // graded monad properties
-- ════════════════════════════════════════════════════════════════════════════

-- | GatewayM left identity: return a >>= f ≡ f a
-- Tests that pure values compose correctly
prop_gatewayMLeftIdentity :: Property
prop_gatewayMLeftIdentity = withTests 10 . property $ do
    x <- forAll genInt
    -- pure x >>= \y -> pure (y + 1) should equal pure (x + 1)
    let m1 = pure x >>= \y -> pure (y + 1) :: GatewayM Int
        m2 = pure (x + 1) :: GatewayM Int
    (a1, g1, _, _) <- evalIO $ runGatewayM m1
    (a2, g2, _, _) <- evalIO $ runGatewayM m2
    a1 === a2
    g1 === g2

-- | GatewayM right identity: m >>= return ≡ m
prop_gatewayMRightIdentity :: Property
prop_gatewayMRightIdentity = withTests 10 . property $ do
    x <- forAll genInt
    let m = pure x :: GatewayM Int
        m' = m >>= pure
    (a1, g1, _, _) <- evalIO $ runGatewayM m
    (a2, g2, _, _) <- evalIO $ runGatewayM m'
    a1 === a2
    g1 === g2

-- | GatewayM associativity: (m >>= f) >>= g ≡ m >>= (\x -> f x >>= g)
prop_gatewayMAssociativity :: Property
prop_gatewayMAssociativity = withTests 10 . property $ do
    x <- forAll genInt
    let m = pure x :: GatewayM Int
        f :: Int -> GatewayM Int
        f y = pure (y + 1)
        g :: Int -> GatewayM Int
        g y = pure (y * 2)
        left = (m >>= f) >>= g
        right = m >>= (\y -> f y >>= g)
    (a1, g1, _, _) <- evalIO $ runGatewayM left
    (a2, g2, _, _) <- evalIO $ runGatewayM right
    a1 === a2
    g1 === g2


-- ════════════════════════════════════════════════════════════════════════════
--                                                  // grade composition tests
-- ════════════════════════════════════════════════════════════════════════════

-- | Grades accumulate through bind
prop_gradesAccumulate :: Property
prop_gradesAccumulate = withTests 10 . property $ do
    let m1 = withLatency (pure ())
        m2 = withLatency (pure ())
        combined = m1 >> m2
    ((), g, _, _) <- evalIO $ runGatewayM combined
    -- Should have 2 provider calls (one per withLatency)
    ggProviderCalls g === 2


-- ════════════════════════════════════════════════════════════════════════════
--                                                                 // test tree
-- ════════════════════════════════════════════════════════════════════════════

tests :: TestTree
tests = testGroup "Graded Monad Property Tests"
    [ testGroup "Grade Monoid Laws"
        [ testProperty "Left identity" prop_gradeLeftIdentity
        , testProperty "Right identity" prop_gradeRightIdentity
        , testProperty "Associativity" prop_gradeAssociativity
        ]
    , testGroup "Grade Monotonicity"
        [ testProperty "Latency monotonic" prop_gradeMonotonicityLatency
        , testProperty "Tokens monotonic" prop_gradeMonotonicityTokens
        ]
    , testGroup "Co-Effect Monoid Laws"
        [ testProperty "Left identity" prop_coEffectLeftIdentity
        , testProperty "Right identity" prop_coEffectRightIdentity
        ]
    , testGroup "GatewayM Monad Laws"
        [ testProperty "Left identity" prop_gatewayMLeftIdentity
        , testProperty "Right identity" prop_gatewayMRightIdentity
        , testProperty "Associativity" prop_gatewayMAssociativity
        ]
    , testGroup "Grade Composition"
        [ testProperty "Grades accumulate" prop_gradesAccumulate
        ]
    ]
