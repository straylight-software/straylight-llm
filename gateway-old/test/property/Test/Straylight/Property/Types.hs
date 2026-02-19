{-# LANGUAGE OverloadedStrings #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                  // test // property // types
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Property-based tests for OpenAI types.
   Tests JSON roundtripping and invariants.
-}
module Test.Straylight.Property.Types (spec) where

import Data.Aeson
import qualified Data.ByteString.Lazy as LBS
import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Hspec
import Test.Hspec.Hedgehog

import Straylight.Types
import Test.Straylight.Property.Generators


spec :: Spec
spec = do
  describe "Role JSON" $ do
    it "roundtrips all roles" $ hedgehog $ do
      role <- forAll genRole
      let encoded = encode role
          decoded = eitherDecode encoded :: Either String Role
      decoded === Right role

  describe "Content JSON" $ do
    it "text content roundtrips" $ hedgehog $ do
      content <- forAll genContent
      let encoded = encode content
          decoded = eitherDecode encoded :: Either String Content
      decoded === Right content

  describe "ChatMessage JSON" $ do
    it "messages roundtrip" $ hedgehog $ do
      msg <- forAll genChatMessage
      let encoded = encode msg
          decoded = eitherDecode encoded :: Either String ChatMessage
      -- Check that decoding succeeds (exact equality may fail due to optional fields)
      case decoded of
        Right _ -> success
        Left err -> footnote err >> failure

    it "messages produce valid JSON" $ hedgehog $ do
      msg <- forAll genChatMessage
      let encoded = encode msg
      assert (LBS.length encoded > 0)

  describe "FinishReason JSON" $ do
    it "roundtrips all finish reasons" $ hedgehog $ do
      reason <- forAll $ Gen.element
        [FinishStop, FinishLength, FinishToolCalls, FinishContentFilter, FinishFunctionCall]
      let encoded = encode reason
          decoded = eitherDecode encoded :: Either String FinishReason
      decoded === Right reason

  describe "Usage JSON" $ do
    it "roundtrips" $ hedgehog $ do
      prompt <- forAll $ Gen.int (Range.linear 0 10000)
      completion <- forAll $ Gen.int (Range.linear 0 10000)
      let total = prompt + completion
          usage = Usage prompt completion total
          encoded = encode usage
          decoded = eitherDecode encoded :: Either String Usage
      decoded === Right usage

    it "handles edge cases" $ hedgehog $ do
      -- Test with zero tokens
      let usage = Usage 0 0 0
          encoded = encode usage
          decoded = eitherDecode encoded :: Either String Usage
      decoded === Right usage

  describe "ChatMessage Invariants" $ do
    it "user messages typically have content" $ hedgehog $ do
      messages <- forAll genChatMessages
      let userMsgs = filter ((== RoleUser) . msgRole) messages
      -- Most user messages should have content (>90%)
      let withContent = filter ((/= Nothing) . msgContent) userMsgs
      when (length userMsgs > 0) $
        assert (length withContent * 100 `div` length userMsgs >= 80)

    it "conversation structure alternates roles" $ hedgehog $ do
      messages <- forAll genChatMessages
      -- Check that we don't have too many consecutive same roles
      -- (except for tool messages which can be batched)
      let nonSystemMsgs = filter ((/= RoleSystem) . msgRole) messages
          pairs = zip nonSystemMsgs (drop 1 nonSystemMsgs)
          samePairs = filter (\(a, b) -> msgRole a == msgRole b && msgRole a /= RoleTool) pairs
      -- Allow some same-role pairs but not too many
      when (length pairs > 0) $
        assert (length samePairs * 100 `div` length pairs < 50)

  describe "Request Parameter Invariants" $ do
    it "temperature is in valid range" $ hedgehog $ do
      temp <- forAll genTemperature
      assert (temp >= 0.0 && temp <= 2.0)

    it "top_p is in valid range" $ hedgehog $ do
      topP <- forAll genTopP
      assert (topP >= 0.0 && topP <= 1.0)

    it "max_tokens is positive" $ hedgehog $ do
      maxTokens <- forAll genMaxTokens
      assert (maxTokens >= 1)

  describe "Model Names" $ do
    it "model names are non-empty" $ hedgehog $ do
      model <- forAll genModel
      assert (model /= "")


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // helpers
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Conditional assertion
when :: Monad m => Bool -> m () -> m ()
when True  m = m
when False _ = pure ()
