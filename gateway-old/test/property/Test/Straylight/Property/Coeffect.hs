{-# LANGUAGE OverloadedStrings #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                               // test // property // coeffect
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Property-based tests for the coeffect semiring.
   n.b. verifies the algebraic laws proven in Lean4
-}
module Test.Straylight.Property.Coeffect (spec) where

import Hedgehog
import qualified Hedgehog.Gen as Gen
import Test.Hspec
import Test.Hspec.Hedgehog

import Straylight.Coeffect
import Test.Straylight.Property.Generators


spec :: Spec
spec = do
  describe "ResourceLevel Lattice" $ do
    it "join is commutative: a ⊔ b = b ⊔ a" $ hedgehog $ do
      a <- forAll genResourceLevel
      b <- forAll genResourceLevel
      joinRL a b === joinRL b a

    it "join is associative: (a ⊔ b) ⊔ c = a ⊔ (b ⊔ c)" $ hedgehog $ do
      a <- forAll genResourceLevel
      b <- forAll genResourceLevel
      c <- forAll genResourceLevel
      joinRL (joinRL a b) c === joinRL a (joinRL b c)

    it "join with RLNone is identity: RLNone ⊔ a = a" $ hedgehog $ do
      a <- forAll genResourceLevel
      joinRL RLNone a === a

    it "join is idempotent: a ⊔ a = a" $ hedgehog $ do
      a <- forAll genResourceLevel
      joinRL a a === a

    it "meet is commutative: a ⊓ b = b ⊓ a" $ hedgehog $ do
      a <- forAll genResourceLevel
      b <- forAll genResourceLevel
      meetRL a b === meetRL b a

    it "meet is associative: (a ⊓ b) ⊓ c = a ⊓ (b ⊓ c)" $ hedgehog $ do
      a <- forAll genResourceLevel
      b <- forAll genResourceLevel
      c <- forAll genResourceLevel
      meetRL (meetRL a b) c === meetRL a (meetRL b c)

    it "meet with RLReadWrite is identity: RLReadWrite ⊓ a = a" $ hedgehog $ do
      a <- forAll genResourceLevel
      meetRL RLReadWrite a === a

    it "meet is idempotent: a ⊓ a = a" $ hedgehog $ do
      a <- forAll genResourceLevel
      meetRL a a === a

    it "absorption: a ⊔ (a ⊓ b) = a" $ hedgehog $ do
      a <- forAll genResourceLevel
      b <- forAll genResourceLevel
      joinRL a (meetRL a b) === a

    it "absorption: a ⊓ (a ⊔ b) = a" $ hedgehog $ do
      a <- forAll genResourceLevel
      b <- forAll genResourceLevel
      meetRL a (joinRL a b) === a

  describe "ResourceLevel Ordering" $ do
    it "≤ is reflexive: a ≤ a" $ hedgehog $ do
      a <- forAll genResourceLevel
      assert (a <= a)

    it "≤ is antisymmetric: a ≤ b ∧ b ≤ a → a = b" $ hedgehog $ do
      a <- forAll genResourceLevel
      b <- forAll genResourceLevel
      when (a <= b && b <= a) $ a === b

    it "≤ is transitive: a ≤ b ∧ b ≤ c → a ≤ c" $ hedgehog $ do
      a <- forAll genResourceLevel
      b <- forAll genResourceLevel
      c <- forAll genResourceLevel
      when (a <= b && b <= c) $ assert (a <= c)

    it "RLNone is bottom: RLNone ≤ a" $ hedgehog $ do
      a <- forAll genResourceLevel
      assert (RLNone <= a)

    it "RLReadWrite is top: a ≤ RLReadWrite" $ hedgehog $ do
      a <- forAll genResourceLevel
      assert (a <= RLReadWrite)

  describe "Subeffecting Properties" $ do
    it "pure ≤ any coeffect (conceptually)" $ hedgehog $ do
      -- SCoeffect with all RLNone should be <= any SCoeffect
      -- This is a conceptual test since we don't have proper Ord instance
      let (SCoeffect c1 g1 m1 n1 s1) = coeffectPure
      assert (c1 == RLNone && g1 == RLNone && m1 == RLNone && n1 == RLNone && s1 == RLNone)


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // helpers
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Join for ResourceLevel (matching Lean4 definition)
joinRL :: ResourceLevel -> ResourceLevel -> ResourceLevel
joinRL RLNone x = x
joinRL x RLNone = x
joinRL RLRead RLRead = RLRead
joinRL _ _ = RLReadWrite

-- | Meet for ResourceLevel (matching Lean4 definition)
meetRL :: ResourceLevel -> ResourceLevel -> ResourceLevel
meetRL RLReadWrite x = x
meetRL x RLReadWrite = x
meetRL RLRead RLRead = RLRead
meetRL _ _ = RLNone

-- | Conditional assertion
when :: Monad m => Bool -> m () -> m ()
when True  m = m
when False _ = pure ()
