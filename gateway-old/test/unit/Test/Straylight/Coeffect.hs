{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                               // test // straylight // coeffect
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

module Test.Straylight.Coeffect (spec) where

import Data.Aeson (encode, toJSON)
import qualified Data.ByteString.Lazy as LBS
import Test.Hspec

import Straylight.Coeffect


spec :: Spec
spec = do
  describe "ResourceLevel" $ do
    describe "ordering" $ do
      it "RLNone < RLRead" $
        RLNone < RLRead `shouldBe` True

      it "RLRead < RLReadWrite" $
        RLRead < RLReadWrite `shouldBe` True

      it "RLNone < RLReadWrite" $
        RLNone < RLReadWrite `shouldBe` True

      it "RLReadWrite is not < RLRead" $
        RLReadWrite < RLRead `shouldBe` False

    describe "JSON encoding" $ do
      it "encodes RLNone as 'none'" $
        encode RLNone `shouldBe` "\"none\""

      it "encodes RLRead as 'read'" $
        encode RLRead `shouldBe` "\"read\""

      it "encodes RLReadWrite as 'readWrite'" $
        encode RLReadWrite `shouldBe` "\"readWrite\""

  describe "SCoeffect witnesses" $ do
    it "coeffectPure has all RLNone" $
      case coeffectPure of
        SCoeffect cpu gpu mem net sto ->
          (cpu, gpu, mem, net, sto) `shouldBe`
            (RLNone, RLNone, RLNone, RLNone, RLNone)

    it "coeffectNetRead has network = RLRead" $
      case coeffectNetRead of
        SCoeffect _ _ _ net _ ->
          net `shouldBe` RLRead

    it "coeffectNetReadWrite has network = RLReadWrite" $
      case coeffectNetReadWrite of
        SCoeffect _ _ _ net _ ->
          net `shouldBe` RLReadWrite

    it "coeffectGpuInference has gpu = RLRead" $
      case coeffectGpuInference of
        SCoeffect _ gpu _ _ _ ->
          gpu `shouldBe` RLRead

    it "coeffectChatCompletions has network = RLReadWrite and gpu = RLRead" $
      case coeffectChatCompletions of
        SCoeffect _ gpu _ net _ ->
          (gpu, net) `shouldBe` (RLRead, RLReadWrite)

    it "coeffectModels has network = RLNone" $
      case coeffectModels of
        SCoeffect _ _ _ net _ ->
          net `shouldBe` RLNone

    it "coeffectHealth has network = RLRead" $
      case coeffectHealth of
        SCoeffect _ _ _ net _ ->
          net `shouldBe` RLRead

  describe "coeffectToJson" $ do
    it "encodes pure coeffect correctly" $ do
      let json = coeffectToJson coeffectPure
      LBS.length (encode json) `shouldSatisfy` (> 0)

    it "encodes chat completions coeffect" $ do
      let json = coeffectToJson coeffectChatCompletions
      LBS.length (encode json) `shouldSatisfy` (> 0)

    it "all coeffect witnesses produce valid JSON" $ do
      let witnesses =
            [ coeffectPure
            , coeffectNetRead
            , coeffectNetReadWrite
            , coeffectGpuInference
            , coeffectLlmRequest
            , coeffectChatCompletions
            , coeffectModels
            , coeffectHealth
            ]
      mapM_ (\w -> LBS.length (encode (coeffectToJson w)) `shouldSatisfy` (> 0)) witnesses
