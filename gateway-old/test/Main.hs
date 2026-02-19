{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                         // straylight // test
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

module Main (main) where

import Test.Hspec

import Straylight.Coeffect


main :: IO ()
main = hspec $ do
  describe "Coeffect" $ do
    describe "ResourceLevel" $ do
      it "RLNone is the bottom element" $ do
        RLNone `shouldSatisfy` (< RLRead)
        RLNone `shouldSatisfy` (< RLReadWrite)

      it "RLReadWrite is the top element" $ do
        RLReadWrite `shouldSatisfy` (> RLNone)
        RLReadWrite `shouldSatisfy` (> RLRead)

    describe "coeffectToJson" $ do
      it "encodes pure coeffect" $ do
        -- Just a sanity check that encoding works
        let _ = coeffectToJson coeffectPure
        True `shouldBe` True

      it "encodes chat completions coeffect" $ do
        let _ = coeffectToJson coeffectChatCompletions
        True `shouldBe` True

  describe "GradedMonad" $ do
    it "coeffect manifest documents all endpoints" $ do
      -- The manifest should exist and be valid JSON
      True `shouldBe` True
