{-# LANGUAGE OverloadedStrings #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                  // test // straylight // types
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

module Test.Straylight.Types (spec) where

import Data.Aeson
import qualified Data.ByteString.Lazy as LBS
import Test.Hspec

import Straylight.Types


spec :: Spec
spec = do
  describe "Role" $ do
    it "parses 'user' correctly" $
      eitherDecode "\"user\"" `shouldBe` Right RoleUser

    it "parses 'assistant' correctly" $
      eitherDecode "\"assistant\"" `shouldBe` Right RoleAssistant

    it "parses 'system' correctly" $
      eitherDecode "\"system\"" `shouldBe` Right RoleSystem

    it "parses 'tool' correctly" $
      eitherDecode "\"tool\"" `shouldBe` Right RoleTool

    it "encodes RoleUser as 'user'" $
      encode RoleUser `shouldBe` "\"user\""

    it "roundtrips correctly" $ do
      let roles = [RoleUser, RoleAssistant, RoleSystem, RoleTool]
      mapM_ (\r -> eitherDecode (encode r) `shouldBe` Right r) roles

  describe "Content" $ do
    it "parses text content from string" $
      eitherDecode "\"Hello, world!\"" `shouldBe` Right (ContentText "Hello, world!")

    it "encodes text content as string" $
      encode (ContentText "Test") `shouldBe` "\"Test\""

  describe "ChatMessage" $ do
    it "parses minimal user message" $ do
      let json = "{\"role\":\"user\",\"content\":\"Hello\"}"
      case eitherDecode json :: Either String ChatMessage of
        Right msg -> do
          msgRole msg `shouldBe` RoleUser
          msgContent msg `shouldBe` Just (ContentText "Hello")
        Left err -> expectationFailure err

    it "parses assistant message without content" $ do
      let json = "{\"role\":\"assistant\"}"
      case eitherDecode json :: Either String ChatMessage of
        Right msg -> do
          msgRole msg `shouldBe` RoleAssistant
          msgContent msg `shouldBe` Nothing
        Left err -> expectationFailure err

    it "roundtrips correctly" $ do
      let msg = ChatMessage
            { msgRole = RoleUser
            , msgContent = Just (ContentText "Test message")
            , msgName = Nothing
            , msgToolCallId = Nothing
            , msgToolCalls = Nothing
            }
      case eitherDecode (encode msg) :: Either String ChatMessage of
        Right decoded -> msgRole decoded `shouldBe` RoleUser
        Left err -> expectationFailure err

  describe "FinishReason" $ do
    it "parses 'stop'" $
      eitherDecode "\"stop\"" `shouldBe` Right FinishStop

    it "parses 'length'" $
      eitherDecode "\"length\"" `shouldBe` Right FinishLength

    it "parses 'tool_calls'" $
      eitherDecode "\"tool_calls\"" `shouldBe` Right FinishToolCalls

    it "encodes FinishStop as 'stop'" $
      encode FinishStop `shouldBe` "\"stop\""

  describe "Usage" $ do
    it "parses usage statistics" $ do
      let json = "{\"prompt_tokens\":10,\"completion_tokens\":20,\"total_tokens\":30}"
      case eitherDecode json :: Either String Usage of
        Right usage -> do
          usagePromptTokens usage `shouldBe` 10
          usageCompletionTokens usage `shouldBe` 20
          usageTotalTokens usage `shouldBe` 30
        Left err -> expectationFailure err

    it "roundtrips correctly" $ do
      let usage = Usage 100 200 300
      eitherDecode (encode usage) `shouldBe` Right usage

  describe "HealthStatus" $ do
    it "encodes HealthOk as 'ok'" $
      encode HealthOk `shouldBe` "\"ok\""

    it "encodes HealthDegraded as 'degraded'" $
      encode HealthDegraded `shouldBe` "\"degraded\""

    it "encodes HealthUnhealthy as 'unhealthy'" $
      encode HealthUnhealthy `shouldBe` "\"unhealthy\""

  describe "ErrorResponse" $ do
    it "encodes error response correctly" $ do
      let err = ErrorResponse $ ErrorDetail
            { errMessage = "Not found"
            , errType = "invalid_request_error"
            , errCode = Nothing
            , errParam = Nothing
            }
      let json = encode err
      LBS.length json `shouldSatisfy` (> 0)
